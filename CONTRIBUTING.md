# Contributing

Thanks for helping. The most useful contributions right now:

- **Test reports from real wheels.** Use the "PS5 test report" issue template, whether the
  PS5 stutter fix worked for you or not.
- **Bug reports** with the step where the app stopped and its logs.
- **Fixes to the app or docs.**

## Before you start

Read [docs/SCOPE.md](docs/SCOPE.md). If your change is outside it, open an issue
first. The instructions for AI assistants are in [CLAUDE.md](CLAUDE.md).

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

## What is not welcome

- Work aimed at a wheel you do not own, or at a device without the owner's consent.
- Thrustmaster's installer, firmware, backups or modified images in git.
- Console authentication or licensing bypass, game-memory changes or cheating.
- Unmasked captures with personal data.
- "It should work" without a pointer.

## Evidence rules

Every factual claim needs at least one:

- `path/to/file:line`
- a flash address (`image`, `0x…`)
- an input SHA-256
- a public URL

And a confidence label:

| Label | Means |
|---|---|
| `proven` | disassembly plus a reproduction in the emulator |
| `likely` | static evidence only |
| `guessed` | inference from related behaviour |

A static finding is never `proven` for "it works". `proven` describes the
evidence, not the outcome.

## Development

You need an Apple Silicon Mac with Swift 6 or newer and CMake 3.21 or newer.

```sh
./script/package_app.sh   # builds dist/T150 Firmware Updater.app and audits it
```

General CI runs the same build and audit automatically for Dependabot-authored
pull requests and remains manually dispatchable. A separate CodeQL security
workflow builds and scans Swift and native C on pushes to `main`, pull requests,
a weekly schedule and manual dispatch. No workflow publishes a binary or
contacts a wheel. Architecture, target profiles and
the release boundary are described in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

Write docs and UI text in plain, short sentences. By contributing you agree that your
contribution is licensed under the [MIT License](LICENSE).
