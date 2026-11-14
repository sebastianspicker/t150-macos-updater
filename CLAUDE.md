# CLAUDE.md

Instructions for Claude Code / AI assistants in this repository. Read this file first, then
[`docs/SCOPE.md`](docs/SCOPE.md).

## Project

Static, host-emulated and on-device interoperability and repair work on the owner's own Thrustmaster T150
racing wheel. Reverse engineering for interoperability is lawful in the EU (Software Directive
2009/24/EC Art. 6; § 69e UrhG). Thrustmaster's official installer contains the T150 V35 firmware. The
firmware has defects and console-mode differences; we find them, document them with evidence, and repair
them on the owner's wheel. That includes decoding the official installer, disassembling and emulating the
extracted firmware, patching copies, rebuilding a pinned image, flashing it through the V5 bootloader, and
recovering the wheel if a flash fails. The V5 bootloader and the console authentication exchange are never
modified.

## Deployment boundary

Deployment is allowed on the owner's own T150, and on a tester's wheel only with that owner's explicit
consent. It is not allowed on any other device. Before a flash:

- confirm the model, application version, bootloader version and USB identity match the profile,
- record the image SHA-256 and the profile name,
- keep the stock V35 image, two fresh flash backups and a working recovery path (V5 bootloader plus
  Thrustmaster's official updater or the app's official-V35 revert),
- record the before/after state and the way back.

A flash can leave the wheel unusable. The recovery path is part of the procedure, not an optional extra.

## Hard rules

1. **Originals are read-only.** Never edit, move or delete `*.exe`, `*.bin`, `*.tmf`, `*.cab`, `*.hdr`,
   `*.image` or evidence captures. `evidence/`, `delivery/`, `src/`, `tools/` and the vendor inputs stay
   out of git.
2. **Work on copies.** Patched images and build products live in `tools/`, `Native/build/` or `dist/`,
   all gitignored.
3. **Hash before and after.** Every installer, image, backup and patch set gets a SHA-256 in the notes or
   in the run record.
4. **Owner's device only.** Patching, rebuilding, flashing, recovery and bootloader reads are in scope on
   the owner's wheel, or on a tester's wheel with explicit consent. Do not point them at another device
   or at a remote target.
5. **Bootloader and authentication stay untouched.** The V5 bootloader (`0x0000`–`0x1fff`) remains
   byte-identical. The I2C authentication exchange with the chip at `0x48` and everything else that is
   console licensing or authentication stays as it is.
6. **No arbitrary images.** Targets are compiled, hash-pinned profiles in `Native/policy.inc`. Never add
   an override that accepts arbitrary images, and never loosen an existing check.
7. **No vendor files in git.** The installer, firmware, decoded images, backups, captures and patch
   sources that contain vendor bytes stay gitignored. Short cited byte excerpts in the notes are
   quotations for evidence.
8. **No `sudo`, no `rm -rf`, no `curl | sh`** unless the user asks. `script/package_app.sh`,
   `script/audit_bundle.sh` and `script/build_and_run.sh --verify` are the safe path.
9. **Flashing is a hardware action.** Never flash or prepare a flash step without the owner's explicit
   confirmation at that moment.
10. **Cite everything.** A claim without a file/address/hash/source is a guess and must be labelled as
    one.

## Scope

In scope: the official Thrustmaster installer, static extraction, string/disassembly analysis, host-side
emulation of extracted firmware and patched copies, firmware comparison across T150 V5/V35 and the T300
RS/T248, documenting defects and console-mode differences, patching copies for repair and
interoperability, deterministic rebuilding and hash-pinning of images, flashing and recovering the
owner's own wheel, and device reads through the V5 bootloader.

Out of scope: other people's wheels without consent, redistribution of firmware/installer/signing
material, console authentication or licensing bypass, game-memory modification or online cheating, and
"guaranteed to work" claims.

Full list and legal basis: [`docs/SCOPE.md`](docs/SCOPE.md). If a task needs something out of scope, add
it to that file first and say so.

## Conventions

- Research notes live in `docs/T150_*.md`, named by topic and never renamed. A new investigation gets a
  new note and a `CHANGELOG.md` entry.
- Every factual row gets a **confidence** label: `proven` (disassembly plus emulator reproduction),
  `likely` (static evidence only), `guessed` (inference). Untested behaviour is `likely` at best.
- Addresses are written as flash offsets and the image is named. Model, application version, bootloader
  version and SHA-256 belong at the top of the note.
- A correction is a new dated paragraph or a `> Correction:` block, not a silent rewrite.
- Keep the tone plain. Short sentences. No marketing.

## Safe commands

```
git status --short
shasum -a 256 <file>
./script/package_app.sh          # build the app, engine and bundle audit
./script/audit_bundle.sh         # check the bundle and run the engine self-test
./script/build_and_run.sh --verify
strings -a <bin> | grep …
objdump -d <bin>                 # ARM Thumb as appropriate
```

Long-running analysis goes to `tools/` (gitignored) only. Flash commands are recorded in the note that
uses them, with the image hash and the recovery step.

## Definition of done

A task is done when:

- the input hash is recorded,
- every claim has a file/address/hash/source,
- confidence is labelled,
- deployment steps name the target, the image hash and the recovery path,
- the relevant doc and `CHANGELOG.md` are updated,
- `./script/package_app.sh` and the bundle audit still pass.

## Deployment checks

Run these yourself before writing to a wheel:

1. Model, application version, bootloader version and USB identity match the profile.
2. The stock V35 image and the recovery path are present.
3. The image and the patched file have recorded SHA-256 values.
4. The wheel is on AC power and directly connected; nothing else is using the USB device.
5. After the flash or restore, read the complete flash back and record the result.

## Boilerplate

When summarising the project, use:

> Interoperability and repair work on the owner's own Thrustmaster T150. Official installer, static
> analysis, host-side emulation, and on-device deployment of a pinned firmware image (patch, rebuild,
> flash, recovery). The goal is a wheel that works correctly on PC and PlayStation, including the ACC
> PS5 stutter.
