# Contributing

Thanks for helping. The most useful contributions right now:

- **Test reports from real wheels.** Use the "PS5 test report" issue template, whether the
  PS5 stutter fix worked for you or not.
- **Bug reports** with the step where the app stopped and its logs.
- **Fixes to the app or docs.**

## Ground rules

- Never commit or attach Thrustmaster's installer, driver, firmware images, wheel backups
  (`*.bin`) or session folders. `.gitignore` blocks the common file types, but check
  `git status` before you commit.
- Changes to the native engine's safety checks (hashes, bootloader protection, patch
  bounds, locks, the double acknowledgement) need a clear reason in the pull request.
  Relaxing a check is rarely the right fix.
- A modified firmware build is never changed in place. A new build gets a new profile
  name and a new pinned SHA-256, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
- Don't run `prepare`, `apply` or `finish` against a wheel as part of a routine test.

## Development

You need an Apple Silicon Mac with Swift 6 or newer and CMake 3.21 or newer.

```sh
./script/package_app.sh   # builds dist/T150 Firmware Updater.app and audits it
```

CI runs the same build and audit on every pull request. Architecture, target profiles and
the release boundary are described in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

Write docs and UI text in plain, short sentences. By contributing you agree that your
contribution is licensed under the [MIT License](LICENSE).
