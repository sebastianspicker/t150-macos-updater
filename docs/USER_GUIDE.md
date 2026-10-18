# User guide

## Before you start

- Use a Mac on AC power and keep it awake with the lid open.
- Connect the wheel directly to the Mac if you can. Hubs add another thing that
  can fail. The first successful update went through hubs, but that says nothing
  about your hub or cable.
- Disconnect other racing wheels and other Thrustmaster devices with their own
  USB plug. Quit games, controller tools, Windows VMs and other updaters.
- Set the T150 switch to **PS3 before connecting USB**, as the
  [official support instructions](https://support.thrustmaster.com/en/product/t150ffb-en/)
  say.
- Mount the wheel securely and keep its full rotation clear. It may turn on its
  own while it calibrates after the restart.

Download the installer from the **Drivers** section of the official support page
and select it in the app. The app checks the whole file, not the name: a changed
file, a different release or a newer installer is refused. Don't use firmware from
other download sites. The app never runs the Windows installer.

## Recovery mode

The app reads and writes the wheel through the T150's bootloader, which Thrustmaster
calls recovery mode. To enter it, follow the
[official bootloader procedure](https://ts.thrustmaster.com/download/accessories/Manuals/T150/T150_Bootloader_Method.pdf):

1. Keep wheel power connected and unplug only the USB cable.
2. Hold **L3 and R3** on the base and reconnect USB while holding both.
3. Release them once the Mac sees the device.

In recovery mode the MODE light may be off and the wheel does not calibrate. That
is expected.

The app tells recovery mode apart from the normal wheel. If it reports an
unsupported bootloader, more than one device, or a missing interface, stop and
keep the error message. Don't try to get around the check by renaming files.

## Backup, review, update, verify

The app walks you through each step:

1. **Choose the installer.** The app checks it and extracts only the T150
   firmware.
2. **Check the wheel.** It reads the wheel's identity and firmware version.
3. **Save two backups.** It reads the complete flash twice and continues only if
   both reads match.
4. **Review.** It shows the installed and new firmware, the image kind, and how
   much data will be written.
5. **Update.** It reads the flash a third time to make sure nothing changed,
   writes only the 4 KiB sectors that differ, then reads everything back and
   compares it with the expected image.
6. **Restart.** Only after a complete match does it restart the wheel and check
   that it reports the new version in normal mode.

During steps 5 and 6, keep USB and power connected. Don't close the app, let the
Mac sleep, switch USB modes, or start another updater. The restart happens
automatically once verification succeeds, so clear the wheel's rotation before you
start. Afterwards, check that calibration and the MODE light look normal.

If the update stops before anything was written (for example because the wheel was
reconnected or the Mac lost AC power), the app says so and asks for new backups.
Each attempt gets its own folder in the session.

### Choosing firmware

This version offers seven V35 builds: the official firmware, "V35 + fixes", and
five experimental builds for the PlayStation 5. All of them are made on your Mac
from the official image and checked against a pinned hash. None changes the
bootloader. [FIRMWARE_BUILDS.md](FIRMWARE_BUILDS.md) explains each one.

A wheel on V35 can switch between these builds in either direction. The app reads
both backups first and only continues if the wheel holds exactly one of the seven
builds. If the wheel already has the build you selected, the app says so and
writes nothing. The app never installs an older version than the wheel has.

### Saved sessions

Every session is saved privately on your Mac:

```text
~/Library/Application Support/T150 Firmware Updater/Sessions/<id>/
```

Use **Show Saved Sessions** in the Help menu, or the session button in the app, to
open it in Finder. It contains:

- `backup-a.bin` and `backup-b.bin`: the two original flash reads
- `manifest.json`: the update plan and device identity
- `readback.bin`: the full read after writing, if the update got that far
- operation logs

A failed session may not have every file. Don't edit or rename files in a session,
and don't move it into a cloud-synced folder while the app uses it.

The backups are copies of your wheel's firmware, and the logs contain device
details. Keep them for support, but don't publish the folder or commit it to a
repository. If someone needs a file, send only that file.

## PlayStation 5 builds

If Assetto Corsa Competizione (ACC) stutters on your PS5 with a T150, choose
**PS5 stutter fix**, marked "Recommended for PS5" in the app. Its full name is
"V35 + sibling mimic + T300 features + recorder". On a tester's T150 it
removed the stutter: several ACC races on the PS5 ran without it, and the wheel
worked fully in the game. That is one owner's result on one wheel, not a
controlled measurement. Other games and hardware revisions have not been tried.

In short, why it works: in PlayStation mode the T150 answers some of the console's
questions differently from Thrustmaster's other wheels. It sends 15-byte vendor
replies where a T300 sends 64 bytes, and it rejects a feature report the T300
answers. This build gives the T300's answers, in PlayStation mode only. The
details, and what is still unknown, are in
[FIRMWARE_BUILDS.md](FIRMWARE_BUILDS.md#the-acc-ps5-stutter).

| Build in the app | Status on a PS5 |
| --- | --- |
| **PS5 stutter fix** | **Fixed the stutter** |
| PS5 stutter patch (first attempt) | Did not change the stutter in an earlier test |
| Sibling mimic | Not tried |
| Sibling mimic + RAW keepalive, PS5 stutter fix + RAW keepalive | Not tried |

The last four are kept for completeness and further testing. The app shows them
under **Other experimental builds**, collapsed. You don't need them for the fix.

Every experimental build needs two acknowledgements before the backup and update
buttons unlock. The second one unlocks after the first. After the PS5 stutter fix
is installed, the app shows the next steps.

### The recorder

The sibling mimic builds count what the console sends in PlayStation mode. This
does not change anything the wheel sends. Once per power-on, when you flip the
PS/PC switch while the wheel is running or when the console suspends USB, the
counts are saved as a 1 KiB record in a separate EEPROM area. Your wheel settings
are stored elsewhere and are not affected.

The tool that reads the record is not published yet. If you want to help find out
which change fixes the stutter, open an issue: a record from a normal ACC session
on the PS5 answers that.

### Going back

To return to the official firmware or switch to another build, enter recovery mode
and run the update again with that build selected.

## If something goes wrong

Keep the session folder and note the step where the app stopped. Writing flash is
not atomic: a failed transfer can leave the application area partly written. The
app stops and never repeats a write or restarts an unverified image on its own.
A disconnected device or a full progress bar does not mean the update worked.

If the wheel stays in recovery mode, leave power and USB as they are while you
collect the logs. The app never writes the first 8 KiB (the bootloader), but that
cannot protect against unrelated hardware or power faults. The app has no
downgrade or one-click restore from a backup.

To recover, use Thrustmaster's bootloader procedure with its Windows updater on a
supported Windows PC, or contact
[Thrustmaster support](https://support.thrustmaster.com/en/product/t150ffb-en/).
Tell them the model, what the wheel shows on USB, the step where it stopped, and
include the logs. Don't publish backup files. Reinstalling this app cannot repair
a wheel.

## Going back to an earlier app version

`script/package_app.sh` keeps one previous build as
`dist/T150 Firmware Updater.previous.app`. Quit the updater once no operation is
running and swap the two apps. This only changes the Mac app, not the wheel's
firmware. Keep your session backups separately from the app.
