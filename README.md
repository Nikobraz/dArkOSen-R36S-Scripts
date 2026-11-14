# R36S USB Mode Switcher

A compact, controller-friendly USB mode selector for **R36S running dArkOSen**. Switch the USB controller's Device Tree setting between **Host**, **Peripheral**, and **OTG** from a terminal-based menu, using the **system's existing controller mappings**.

> [!WARNING]
> This tool **modifies the boot DTB**. An incompatible setting may disable USB devices or USB networking, and could require recovering the microSD card on a computer. **Back up your working TF1 card before making changes.**

## Features

- **Three USB modes:** `host`, `peripheral`, and `otg`.
- **Compact `dialog` menu** designed for the R36S display.
- **Built-in controller navigation** via dArkOSen's existing `/opt/inttools/keys.gptk` and `gptokeyb`; no custom button layout.
- **Status screen** showing the saved DTB mode, live Device Tree mode, PHY state, and USB Device Controller (UDC) state.
- **First-change backup** plus a timestamped DTB snapshot before each modification.
- **Restore option** to return to the first saved DTB.
- **Optional OTG PHY activation** when its node is marked `disabled`.
- **Reboot prompt** after changes, with a diagnostic log.
- **Single-file installation:** no separate EmulationStation launcher is needed when the script is placed in the configured tools directory.

## Compatibility

Designed around this configuration:

| Component | Target |
| --- | --- |
| Device | R36S (BOYHOM V22, 2025-09-22, batch 2551) |
| OS | dArkOSen, including the 10312026 branch |
| Boot DTB | `/boot/rk3326-r36s-linux.dtb` |
| USB controller node | `/usb@ff300000` |
| USB PHY node | `/syscon@ff2c0000/usb2-phy@100/otg-port` |
| Controller mapping | `/opt/inttools/keys.gptk` |

**Other boards, kernels, DTBs, and firmware builds are not verified.** The script checks for the expected DTB and boot configuration and exits if they are missing. A successful edit does **not** guarantee that a particular USB role is supported by the board, kernel, or cable.

## Requirements

- Bash and a working terminal/virtual console.
- Root privileges (`sudo` for interactive terminal use; non-interactive `sudo` permissions when launched by EmulationStation as a non-root user).
- `dialog` for the menu.
- `device-tree-compiler`, providing `dtc`, `fdtget`, and `fdtput`.
- dArkOSen's `/opt/inttools/gptokeyb` and `/opt/inttools/keys.gptk`.
- A working `/dev/uinput` device; the script attempts to load its module if needed.
- The TF1 BOOT partition mounted at `/boot` and enough free space for backups.

Install the Debian-packaged tools if necessary:

```bash
sudo apt update
sudo apt install dialog device-tree-compiler
```

The remaining tools and controller mapping are normally provided by the target dArkOSen installation.

## Installation

1. **Create a complete backup of the working TF1 microSD card on a PC.** Keep a separate copy of its original BOOT files.
2. Copy `R36S_USB_Mode_SystemKeys.sh` to `/home/ark/` on the R36S.
3. Install the script into the tools directory:

   ```bash
   sudo install -m 755 \
     /home/ark/R36S_USB_Mode_SystemKeys.sh \
     "/opt/system/Tools/USB Mode Switcher.sh"
   ```

4. Open **Options → Tools → USB Mode Switcher** if this entry is exposed by your EmulationStation configuration.

Or launch it directly from a terminal:

```bash
sudo bash "/opt/system/Tools/USB Mode Switcher.sh"
```

> [!NOTE]
> The EmulationStation launcher must allow a usable virtual console. If it runs the script as a non-root user, `sudo -n` must be permitted; the script cannot display an interactive password prompt in that launch path. Do not enable unrestricted passwordless `sudo` just to make this tool work.

## Usage

Use the **D-pad** to move through the menu and the system-mapped confirm/cancel buttons to select or exit. The exact button mappings come from **`/opt/inttools/keys.gptk`**, including any customizations made by dArkOSen's Button Mapper.

```text
          R36S USB

 Saved: otg

 host         Keyboard / WiFi / BT
 peripheral   USB network to PC
 otg          Dual role
 status       Show current status
 restore      Restore first backup
 exit         Exit
```

### USB modes

| Mode | Intended use | Important limitation |
| --- | --- | --- |
| `host` | USB keyboards, hubs, Wi-Fi and Bluetooth dongles | The same controller may no longer work as a USB device connected to a PC. |
| `peripheral` | USB device/gadget operation, such as RNDIS to a PC | USB host accessories on that controller may stop working. |
| `otg` | Both USB roles where supported | Automatic role switching depends on hardware, kernel, PHY settings, and cabling. |

To change the mode:

1. Select `host`, `peripheral`, or `otg`.
2. Confirm the warning and backup prompt.
3. If offered, decide whether to enable the currently disabled OTG PHY. **This is experimental.**
4. The script writes and validates a temporary copy, then replaces the configured boot DTB.
5. Choose whether to reboot. **The new setting takes effect only after reboot.**

**Changing `dr_mode` does not itself start RNDIS, assign IP addresses, or share an internet connection.** For USB networking, use the appropriate **USB Network Mode** utility after the controller is working in device mode.

### Status screen

The `status` option shows:

- **Saved:** `dr_mode` stored in the DTB on BOOT (used at next boot).
- **Live:** `dr_mode` exposed by the currently running kernel.
- **PHY:** the `status` property in the saved DTB's OTG PHY node.
- **UDC:** the current USB Device Controller state, such as `configured`, `not attached`, or `unavailable`.

The saved and live values may differ **until the next reboot**.

## Backups and recovery

On the first change, the script creates a baseline backup if one does not already exist:

```text
/boot/rk3326-r36s-linux.dtb.usb-original.bak
```

Before every change, it also creates a timestamped backup similar to:

```text
/boot/rk3326-r36s-linux.dtb.usb-backup.YYYYMMDD-HHMMSS-PID
```

**Important:** the baseline is a copy of the DTB **at the time of the first change**, not necessarily the manufacturer's original DTB. Existing baseline backups are never overwritten by the script.

### Restore from the menu

Select **`restore` → `Restore first backup`**, confirm, and reboot.

### Restore if the R36S cannot be controlled

1. Power off the console.
2. Remove the TF1 microSD and connect it to a PC using a card reader.
3. Open the BOOT partition and preserve any existing files for diagnosis.
4. Copy your known-good DTB (or the `.usb-original.bak` backup) to `rk3326-r36s-linux.dtb` on BOOT.
5. Safely eject the card, insert it into TF1, and reboot.

Do **not** assume a DTB from another board revision will be compatible, even if the filename is identical.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Menu does not appear in EmulationStation | Script permissions, root access, active TTY, `dialog`, and the diagnostic log. |
| Menu opens but the gamepad does not respond | `gptokeyb`, `/dev/uinput`, the system `keys.gptk`, and controller database. |
| `Missing command: fdtget` or `fdtput` | Install `device-tree-compiler`. |
| `BOOT is not mounted at /boot` | Confirm where your firmware mounts the boot partition; do not blindly edit another file. |
| `boot.ini uses another DTB` | This build expects `rk3326-r36s-linux.dtb`; review your boot setup before modifying paths. |
| RNDIS does not appear after selecting `peripheral` | Confirm USB Gadget setup, the USB Network Mode service, data-capable OTG cable, and UDC state. |
| USB keyboard/dongle stops working | Restore `otg` or a known-good DTB using a card reader if necessary. |
| Black screen or failed boot after editing | Recover BOOT from your external backup; avoid repeated blind edits. |

Inspect the log:

```bash
cat /home/ark/r36s-usb-mode.log
```

To inspect the currently running kernel's DTB mode:

```bash
tr -d '\0' < /proc/device-tree/usb@ff300000/dr_mode
echo
```

To check the USB Device Controller:

```bash
ls /sys/class/udc/
cat /sys/class/udc/*/state
```

## Implementation notes

The script uses `fdtget`/`fdtput` to edit only its configured DTB, then checks the result with `dtc`. It does **not** change the kernel `Image`, `boot.ini`, or the separate U-Boot DTB.

It launches `gptokeyb` with the system file:

```bash
/opt/inttools/gptokeyb -1 "USB Mode Switcher.sh" \
  -c /opt/inttools/keys.gptk
```

It **does not modify `keys.gptk`**. However, it terminates existing `gptokeyb` processes before starting its own mapper; avoid running it alongside another terminal application that depends on `gptokeyb`.

## Safety and limitations

- Designed for **testing**, not guaranteed universal USB role switching.
- Editing a DTB requires **root access** and a **reboot** to take effect.
- Enabling a disabled USB PHY is an **experimental change** and can break existing USB behavior.
- The script does not repair incompatible kernels, USB PHY wiring, or missing Gadget modules.
- Keep a complete off-device TF1 backup: an on-card backup alone is insufficient if the console stops booting.
- Controller input is inherited from dArkOSen. If the system key mapping does not provide the expected menu keys, navigation may not work.

## Contributing

If you test another R36S revision, include the **board marking**, **dArkOSen version**, **DTB model**, selected mode, and relevant excerpts from `/home/ark/r36s-usb-mode.log` in your bug report. Do not publish passwords, private keys, or unrelated personal files.

## License

This project is licensed under the **MIT License**.

You are free to use, copy, modify, merge, publish, distribute, sublicense, and sell copies of this software, provided that the original copyright notice and license terms are included.

This software is provided "AS IS", without warranty of any kind.

See the [LICENSE](LICENSE) file for the full license text.
