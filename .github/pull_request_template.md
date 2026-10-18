## What and why

<!-- What does this change, and why? Link the issue if there is one. -->

## Checks

- [ ] `./script/package_app.sh` passes
- [ ] No installer, driver, firmware image, backup or session file is added
- [ ] Docs and CHANGELOG.md updated if behaviour or text changed

## Firmware builds

<!-- Only if a patch table in Native/policy.inc or a target in FirmwareProfile.swift changes. -->

- [ ] New build name, new profile and new pinned SHA-256 (existing profiles never change)
- [ ] Every entry stays in 0x2000 to 0xfff7 and is at most 8 bytes
- [ ] How the image was checked (static review, emulator) is described above
