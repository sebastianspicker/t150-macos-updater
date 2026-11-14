# Security

This app writes firmware to a USB device, so a bug in its checks can damage hardware.

## Scope

This repository covers interoperability and repair work on the owner's own
Thrustmaster T150. It does not target other people's wheels, redistribute
Thrustmaster's installer or firmware, bypass console authentication, or modify
games. See [docs/SCOPE.md](docs/SCOPE.md).

## Risk classes

| Class | Meaning |
|---|---|
| `read-only` | extraction, strings, disassembly, emulator runs; no device contact |
| `flash` | replaces firmware on the owner's wheel; stock image, backups and recovery path recorded |

Every write procedure must name its class and its revert or recovery path.

## Reporting a safety problem

Please report anything that could make the app:

- write an image that is not one of its pinned builds
- write to the bootloader area (the first 8 KiB)
- run code from the selected installer, or a tool from outside the app bundle
- read or write files outside its own support folder and session folders

Report privately through GitHub's **Report a vulnerability** button on the Security tab
of this repository. Please don't open a public issue for these. Include the app version,
macOS version and the steps to reproduce.

A firmware update can also fail for reasons that are not security issues, for example a
USB cable or power loss. Use a normal bug report for those.
