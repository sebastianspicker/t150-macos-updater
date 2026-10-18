# Security

This app writes firmware to a USB device, so a bug in its checks can damage hardware.
Please report anything that could make it:

- write an image that is not one of its pinned builds
- write to the bootloader area (the first 8 KiB)
- run code from the selected installer, or a tool from outside the app bundle
- read or write files outside its own support folder and session folders

Report privately through GitHub's **Report a vulnerability** button on the Security tab
of this repository. Please don't open a public issue for these. Include the app version,
macOS version and the steps to reproduce.

A firmware update can also fail for reasons that are not security issues, for example a
USB cable or power loss. Use a normal bug report for those.
