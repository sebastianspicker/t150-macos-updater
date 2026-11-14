# Scope and framing

This repository covers **interoperability and repair work on hardware the author owns**: Thrustmaster T150
racing wheels that the author owns, plus one tester's wheel with that owner's explicit consent. Reverse
engineering for interoperability is lawful in the EU. The project separates **analysis** from
**deployment**, but both are in scope when the target is an owned device. It is not a project about other
people's hardware, and it does not redistribute firmware, installers or modified images.

## The one-sentence framing

> Thrustmaster's T150 firmware has defects that can lock up the wheel and console-mode behaviour that makes
> the PS5 version of ACC stutter. This project reads the official firmware from the installer the owner
> downloads, documents what is wrong, and rebuilds a pinned, reviewed image for the owner's own wheel —
> through the vendor's bootloader, with the stock image and recovery path kept.

## In scope

| Activity | Why it is in scope |
|---|---|
| Downloading the official Thrustmaster installer | It is published for free on the T150 support page |
| Hashing the installer and parsing it statically | Pure observation; the Windows installer is never executed |
| Extracting the official V35 firmware payload | The firmware is data inside the installer |
| Reading the owner's own wheel flash through the V5 bootloader | The wheel belongs to the owner; two backups are kept |
| `strings`, `objdump`, disassembly, decompilation | Read-only analysis of copies |
| Running extracted firmware in an emulator | Tests behaviour without touching hardware |
| Comparing V5/V35/T300 RS/T248 firmware | Establishes what differs and why |
| Documenting defects, console differences and confidence | Makes the result falsifiable |
| Patching copies of V35 for defect repair and interoperability | The patch is the mechanism that fixes the defect or makes the console reply match the siblings |
| Rebuilding the image deterministically and pinning its SHA-256 | Required for a reviewed, repeatable target |
| Flashing a pinned image to the owner's wheel | The deployment step for this project |
| Recovering the wheel to stock V35 | The way back if a build or flash fails |
| Writing documentation, hashes and recovery steps | Reproducibility and safety |

## Out of scope

- **Other devices.** Nothing aimed at a wheel the author does not own, or at a device without the owner's
  explicit consent.
- **Redistribution.** The installer, firmware, decoded images, backups, captures and authentication
  material stay gitignored; only hashes and notes are committed. Short byte excerpts in the notes are
  quotations for citation.
- **Authentication or licensing bypass.** The I2C authentication exchange and everything else that is
  console licensing or authentication stays untouched. The sibling-mimic builds change USB replies the
  console requests; they do not bypass console authentication.
- **Game modification or cheating.** No game memory, save, network or anti-cheat changes. The work is
  limited to the wheel's USB and firmware behaviour.
- **"Guaranteed to work" claims.** Static findings are labelled as such until tested on hardware.

## Legal basis (short)

- **EU Software Directive 2009/24/EC, Article 6** allows decompilation/reverse engineering for
  interoperability without the rightsholder's authorisation, subject to the Article 6 conditions: a
  lawful acquirer, acts indispensable to obtain the interoperability information, information not
  readily available, and use limited to interoperability. Germany implements this in **§ 69e UrhG**.
  Article 8 makes contract terms that contradict Article 6 null and void. This covers reading, analysis
  and patching a lawfully obtained copy for interoperability testing.
- The firmware is obtained from the **official installer** the owner downloads; the project does not
  redistribute it.
- The work is on the **owner's own wheel**, with the stock image and recovery path kept. One tester's
  wheel was used with that owner's explicit consent.
- A modified image can affect warranty and vendor support; that is the owner's decision.
- Community interoperability work on game controllers is established practice, for example the Linux
  `hid-thrustmaster` driver and the `t150_driver` project cited in these notes. This project stays within
  that practice.

## Risk and recovery

Every deployment step names:

- the exact image or artifact hash,
- the profile and the model/application/bootloader it targets,
- the recovery path (stock V35 through the V5 bootloader, Thrustmaster's official Windows updater, or the
  app's official-V35 revert).

A flash that fails is not a reason to skip the step; it is a reason to write the recovery path down first.
The V5 bootloader is never changed, so manual bootloader entry remains available even if the application
misbehaves. The stock V35 image and the two backups are the way back.

## How to describe the project

> Interoperability and repair work on the owner's own Thrustmaster T150. Official installer, static
> analysis, host-side emulation, and on-device deployment of a pinned firmware image (patch, rebuild,
> flash, recovery). Goal: a wheel that works correctly on PC and PlayStation, including the ACC PS5
> stutter.

## Change control

Changes to this scope need a note in `CHANGELOG.md` or the relevant doc. If a task seems to need something
on the out-of-scope list, stop and add it here first rather than silently widening the project.

Revision history:

- **2026-11-14:** first written scope; legal basis and owner-device deployment boundary made explicit.
