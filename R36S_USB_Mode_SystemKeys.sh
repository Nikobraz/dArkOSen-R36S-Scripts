#!/usr/bin/env bash
# R36S / dArkOSen: USB DTB mode switcher using system controller mappings.
# Single-file launcher for EmulationStation Options/Tools or a terminal.
# All UI text is ASCII. Changes apply AFTER reboot.
set -Eeuo pipefail
export LC_ALL=C
export TERM=linux
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

SELF="$(readlink -f -- "$0")"
LOG='/home/ark/r36s-usb-mode.log'
BOOT='/boot'
BOOTINI="$BOOT/boot.ini"
BASELINE="$BOOT/rk3326-r36s-linux.dtb.usb-original.bak"
USB_NODE='/usb@ff300000'
PHY_NODE='/syscon@ff2c0000/usb2-phy@100/otg-port'
GPTOKEYB='/opt/inttools/gptokeyb'
KEYS='/opt/inttools/keys.gptk'
JOYDB='/opt/inttools/gamecontrollerdb.txt'
TTY_DEVICE=''
DTB_TMP=''
GPT_PID=''

log() { printf '%s %s\n' "$(date -Is 2>/dev/null || date)" "$*" >> "$LOG" 2>/dev/null || true; }


# Detect active DTB from boot.ini

if [[ ! -f "$BOOTINI" ]]; then
    echo "ERROR: boot.ini not found"
    exit 1
fi

DTB_NAME=$(awk '
    $1 == "load" && $2 == "mmc" && $4 == "${dtb_loadaddr}" {
        print $5
        exit
    }
' "$BOOTINI" | tr -d '\r"')

if [[ -z "$DTB_NAME" ]]; then
    echo "ERROR: Cannot detect DTB from boot.ini"
    exit 1
fi

DTB="${BOOT}/${DTB_NAME#./}"

if [[ ! -f "$DTB" ]]; then
    echo "ERROR: DTB file not found: $DTB"
    exit 1
fi

echo "Detected DTB: $DTB"

BASELINE="$BOOT/${DTB_NAME#./}.usb-original.bak"

# Escalate privileges. The ES menu often has no password-entry TTY.
if (( EUID != 0 )); then
    if [[ -t 0 && -t 1 ]]; then
        exec sudo /bin/bash "$SELF" "$@"
    fi
    exec sudo -n /bin/bash "$SELF" --es
fi

# The ES launcher does not always pass a usable interactive terminal.
if [[ "${1:-}" == '--es' || ! -t 0 || ! -t 1 ]]; then
    current_tty="$(cat /sys/class/tty/tty0/active 2>/dev/null || true)"
    [[ "$current_tty" =~ ^tty[0-9]+$ ]] || current_tty='tty1'
    TTY_DEVICE="/dev/$current_tty"
    if [[ ! -r "$TTY_DEVICE" || ! -w "$TTY_DEVICE" ]]; then
        log "ERROR: no accessible TTY: $TTY_DEVICE"
        exit 1
    fi
    exec < "$TTY_DEVICE" > "$TTY_DEVICE" 2>&1
else
    TTY_DEVICE="$(tty 2>/dev/null || true)"
fi

# Use compact dialog dimensions for the R36S 640x480 display.
export DIALOGRC=''
if [[ -f /opt/inttools/noshadows.dialogrc ]]; then
    export DIALOGRC=/opt/inttools/noshadows.dialogrc
fi

msg() { dialog --no-shadow --title "$1" --msgbox "$(printf '%b' "$2")" 9 36; }
ask() { dialog --no-shadow --title "$1" --yesno "$(printf '%b' "$2")" 9 36; }
fail() { log "ERROR: $*"; msg 'Error' "$*" || true; exit 1; }

cleanup() {
    local code=$?
    trap - EXIT
    if [[ -n "$GPT_PID" ]]; then
        kill "$GPT_PID" 2>/dev/null || true
        wait "$GPT_PID" 2>/dev/null || true
    fi
    [[ -z "$DTB_TMP" ]] || rm -f -- "$DTB_TMP"
    # Never modify the system keymap. DTB backups remain untouched.
    [[ -z "$TTY_DEVICE" || ! -w "$TTY_DEVICE" ]] || printf '\033[?25h' > "$TTY_DEVICE" 2>/dev/null || true
    log "Exit code: $code"
}
trap cleanup EXIT

for bin in dialog fdtget fdtput dtc mountpoint mktemp; do
    command -v "$bin" >/dev/null 2>&1 || fail "Missing command: $bin"
done
[[ -x "$GPTOKEYB" && -r "$KEYS" ]] || fail 'gptokeyb or keys.gptk missing.'
mountpoint -q "$BOOT" || fail 'BOOT is not mounted at /boot.'
[[ -f "$DTB" && -r "$BOOTINI" ]] || fail 'BOOT DTB or boot.ini missing.'
grep -Fq 'rk3326-r36s-linux.dtb' "$BOOTINI" || fail 'boot.ini uses another DTB.'
fdtget -t s "$DTB" "$USB_NODE" dr_mode >/dev/null 2>&1 || fail 'USB node not present in DTB.'

# Respect the system Button Mapper configuration exactly as it is.
# Do not create a temporary .gptk file or override any button mapping.
log "Using system gptokeyb map: $KEYS"

[[ -c /dev/uinput ]] || { command -v modprobe >/dev/null 2>&1 && modprobe uinput 2>/dev/null || true; }
[[ -c /dev/uinput ]] || fail 'No /dev/uinput device.'
[[ -r "$JOYDB" ]] && export SDL_GAMECONTROLLERCONFIG_FILE="$JOYDB"

# dArkOSen tools use gptokeyb to map gamepad buttons to terminal keys.
# Like the system tools, stop any old mapper before starting a private one.
pkill -TERM -x gptokeyb 2>/dev/null || true
sleep 0.2
"$GPTOKEYB" -1 "$(basename -- "$SELF")" -c "$KEYS" >> "$LOG" 2>&1 &
GPT_PID=$!
sleep 0.3
if ! kill -0 "$GPT_PID" 2>/dev/null; then
    log 'WARNING: gptokeyb exited immediately; check system keymap and log.'
    msg 'Gamepad issue' 'gptokeyb did not start.\nCheck keys.gptk or use a keyboard.' || true
fi

saved_mode() { fdtget -t s "$DTB" "$USB_NODE" dr_mode 2>/dev/null || printf 'unknown'; }
phy_status() { fdtget -t s "$DTB" "$PHY_NODE" status 2>/dev/null || printf 'unknown'; }
live_mode() {
    if [[ -r "/proc/device-tree${USB_NODE}/dr_mode" ]]; then
        tr -d '\0' < "/proc/device-tree${USB_NODE}/dr_mode"
    else
        printf 'unknown'
    fi
}
udc_status() {
    local state
    for state in /sys/class/udc/*/state; do
        [[ -r "$state" ]] && { cat "$state"; return; }
    done
    printf 'unavailable'
}

backup_dtb() {
    if [[ ! -f "$BASELINE" ]]; then
        cp -p -- "$DTB" "$BASELINE" || fail 'Baseline backup failed.'
    fi
    local snap="${DTB}.usb-backup.$(date +%Y%m%d-%H%M%S)-$$"
    cp -p -- "$DTB" "$snap" || fail 'Snapshot backup failed.'
    log "Saved backup: $snap"
}
prepare_copy() {
    DTB_TMP="$(mktemp "$BOOT/.r36s-usb.XXXXXX")" || fail 'Cannot create temporary DTB.'
    cp -p -- "$1" "$DTB_TMP" || fail 'Cannot prepare temporary DTB.'
}
commit_dtb() {
    dtc -q -I dtb -O dts -o /dev/null "$DTB_TMP" || fail 'DTB validation failed.'
    mv -f -- "$DTB_TMP" "$DTB" || fail 'Cannot write boot DTB.'
    DTB_TMP=''
    sync
}
finish() {
    local text="$1"
    log "$text"
    if ask 'Saved' "$text\n\nReboot now?"; then
        reboot
    fi
}

while :; do
    # Keep the title/descriptions short to avoid clipping on R36S displays.
    selected="$(dialog --no-shadow --clear \
        --title 'R36S USB' \
        --menu "Saved: $(saved_mode)" 14 38 6 \
        host       'Keyboard / WiFi / BT' \
        peripheral 'USB network to PC' \
        otg        'Dual role' \
        status     'Show current status' \
        restore    'Restore first backup' \
        exit       'Exit' \
        3>&1 1>&2 2>&3)" || break

    case "$selected" in
        status)
            msg 'USB status' "Saved: $(saved_mode)\nLive: $(live_mode)\nPHY: $(phy_status)\nUDC: $(udc_status)" || true
            ;;
        exit) break ;;
        restore)
            [[ -f "$BASELINE" ]] || { msg 'No backup' 'No baseline DTB found.'; continue; }
            if ask 'Restore' 'Restore first saved DTB?\nReboot required.'; then
                backup_dtb
                prepare_copy "$BASELINE"
                commit_dtb
                finish 'Backup restored.'
            fi
            ;;
        host|peripheral|otg)
            if [[ "$selected" == "$(saved_mode)" ]]; then
                msg 'No change' "Already set: $selected" || true
                continue
            fi
            ask 'Confirm' "Set: $selected\nUSB may stop working.\nSave backup and apply?" || continue
            enable_phy=0
            if [[ "$(phy_status)" == 'disabled' ]]; then
                if ask 'USB PHY' 'OTG PHY is disabled.\nEnable it? (test)'; then
                    enable_phy=1
                fi
            fi
            backup_dtb
            prepare_copy "$DTB"
            fdtput -t s "$DTB_TMP" "$USB_NODE" dr_mode "$selected" || fail 'Could not set USB mode.'
            [[ "$(fdtget -t s "$DTB_TMP" "$USB_NODE" dr_mode)" == "$selected" ]] || fail 'Mode verification failed.'
            if (( enable_phy )); then
                fdtput -t s "$DTB_TMP" "$PHY_NODE" status okay || fail 'Could not enable PHY.'
                [[ "$(fdtget -t s "$DTB_TMP" "$PHY_NODE" status)" == okay ]] || fail 'PHY verification failed.'
            fi
            commit_dtb
            finish "Saved: $selected"
            ;;
        *) fail 'Unknown choice.' ;;
    esac
done
exit 0
