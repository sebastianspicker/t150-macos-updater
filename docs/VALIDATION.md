# Validation record

What has been tested, on what, and what has not. Version history is in the
[changelog](../CHANGELOG.md), and the firmware builds are described in
[FIRMWARE_BUILDS.md](FIRMWARE_BUILDS.md).

Development machine: Apple Silicon (arm64), macOS 27.0.1, Apple Swift 6.4,
CMake 4.4.4. The app targets macOS 14, but it has not been run on macOS 14.

## On real wheels

| Date | Wheel | What was done | Result |
| --- | --- | --- | --- |
| 2026-10-17 | T150, application V5, bootloader V5 | Update to official V35 with the native engine, before the GUI existed | Complete flash readback matched, bootloader unchanged, normal-mode V35, calibration and MODE light normal |
| 2026-10-18 | Second T150 | "V35 + fixes + PS5 stutter patch" flashed | Tester report: ACC PS5 stutter unchanged |
| 2026-10-18 | Same second T150, presumably | "V35 + sibling mimic + T300 features + recorder" flashed with the packaged GUI (0.5.0) | GUI confirmed the complete image, the unchanged bootloader and normal-mode V35. Several ACC races on the PS5 without stutter, wheel fully working |

The ACC results are the owner's reports. There were no frame-time or USB
measurements, and the ACC build number and settings were not recorded. Whether
the patch build was flashed through the GUI is not recorded either.

## Offline checks for 0.6.0

The maintainer's offline test suite (not part of this repository), run on the
development Mac:

- Swift Testing: 9 tests passed. The optional real-installer import test was
  skipped because no installer path was set.
- Native engine `self-test` passed.
- 73 offline workflow cases passed. They cover a V7 starting image, manifest
  reload, mismatched backups, a changed device identity, refused same-version
  and downgrade updates, write failures, failures without a reset, a fresh
  verification before restart, durable retry markers, failed writes of session
  files, the AC power check, every pair of the seven V35 builds in both
  directions, already-installed builds, unknown V35 images, and tampered profiles.
- The GUI and the engine list the same 7 pinned targets, and every same-version
  baseline is another compiled target.
- CLI checks: confirmations, invalid sessions and profiles, symlink and
  permission refusal, result preservation. No USB access.

With real firmware fixtures (a stock V35 flash readback and the decoded installer
image), the workflow tests also build
every modified image from real bytes. Each must match its pinned hash from stock
V35, from every other build and from an older version, and must revert
byte for byte. A flipped byte in the added code, a tampered footer and partial
patch sets are refused. That run last passed for 0.5.0. The fixtures are not
distributed.

`./script/package_app.sh` built 0.6.0 (7) and the bundle audit passed, including
the app icon check. Local archive `dist/T150-Firmware-Updater-macOS-arm64.zip`,
864,464 bytes, SHA-256
`3672bdbe352bc7d8588c7a63bb62f6f610c1cd58ec5e048987941859066b6677`. Ad-hoc
signature only, not notarized. The zip hash changes with every packaging run, because the archive stores
file times; this one is from `./script/build_and_run.sh --verify`, which packages
again before launching.

## Bundle checks

`script/audit_bundle.sh` runs after every package build. It checks:

- the plist, the app icon and the required third-party notices
- strict ad-hoc signatures on every executable and the app
- that each executable targets macOS 14 and links only system libraries
- that no developer home or Homebrew path is embedded
- that no installer, driver or firmware file is bundled
- the offline self-tests of the bundled tools

## The GUI

The app was launched through Launch Services, and its window was registered.
A person checked the welcome screen. There are no automated UI tests: macOS denied
accessibility access and screen capture in the development environment. Real
installer import is covered by an optional test in the private suite, not by clicking through
the packaged app.

## Not validated

- other starting firmware versions than V5 and V35, other bootloaders, other
  wheel models
- downgrades, power loss during an update, automatic restore from a backup
- Intel Macs and macOS versions other than 27
- games on macOS, and force feedback on macOS (the app does not install a
  driver)
- the experimental builds other than "sibling mimic + T300 features" on a
  console
