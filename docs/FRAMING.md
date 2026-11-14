# Framing card

Copy-paste text for issues, READMEs and chat openers.

## Short

> Interoperability and repair work on the owner's own Thrustmaster T150. Official installer, static
> analysis, host-side emulation, and on-device deployment of a pinned firmware image (patch, rebuild,
> flash, recovery). Goal: a wheel that works correctly on PC and PlayStation, including the ACC PS5
> stutter.

## One paragraph

> Thrustmaster's T150 firmware V35 has defects that can lock up the wheel and console-mode behaviour that
> appears to trigger a stutter in the PS5 version of Assetto Corsa Competizione. The code is read from the
> official installer the owner downloads, not from a redistributed image. This project unpacks the
> installer, disassembles the firmware, reproduces the defects in an emulator, and documents the console
> differences against Thrustmaster's own T300 RS and T248. Fixes are built on the owner's Mac from the
> official image plus a reviewed, hash-pinned patch table, installed through the V5 bootloader on the
> owner's wheel, and verified by reading the complete flash back. The bootloader and console
> authentication are never changed. Current status: the PS5 stutter fix removed the stutter on one
> tester's T150 over several ACC races; the other builds are kept for testing. See
> [`SCOPE.md`](SCOPE.md).

## What it is / is not

| It is | It is not |
|---|---|
| firmware interoperability and repair research | a project against other people's devices |
| official installer plus a from-source patched image for the owner's wheel | a redistributed custom-firmware build |
| analysis, emulation, patch, rebuild, flash, recovery | a claim that the result is guaranteed |
| an owned wheel and an owned console | a remote or third-party target |
| a USB/firmware compatibility change | a console authentication or game-memory bypass |

## Q&A for reviewers

**Is this legal?**
Decompilation for interoperability is allowed without authorisation under Art. 6 of Directive 2009/24/EC
and § 69e UrhG, subject to the Article 6 conditions; Art. 8 makes contrary contract terms void. The
firmware comes from the official installer; the work is on the owner's own wheel. See
[`SCOPE.md`](SCOPE.md).

**Does it modify the firmware?**
Yes, for the modified builds. The app builds each one on the Mac from the official V35 image plus a
compiled patch table; every entry asserts its original bytes, stays inside `0x2000`–`0xfff7`, and the
complete image must match a pinned SHA-256. The V5 bootloader (`0x0000`–`0x1fff`) and the console
authentication exchange are never changed. The official V35 build is Thrustmaster's image unchanged.

**Can it brick the wheel?**
A bad flash can leave the application unusable. The V5 bootloader is never changed, so manual bootloader
entry (L3 + R3) and either the app's official-V35 revert or Thrustmaster's official Windows updater remain
available. The app reads the complete flash twice before writing, writes only differing application
sectors, verifies the full image, and keeps the two backups. Every deployment step records the image hash
and the way back before it writes anything.

**Why the T300 RS and T248?**
They are Thrustmaster's other PlayStation-licensed wheels. All three present the same USB identity and HID
report descriptor to the console, but the T150 sends shorter vendor replies and rejects feature report
0x49. The sibling-mimic builds make the T150 answer the way the T300 does, in PlayStation mode only; the
identity reply still says T150. That is an interoperability change, not an authentication bypass.

**Is this cheating?**
No. The builds change how the wheel answers USB requests; they do not touch game memory, saves, network
traffic or anti-cheat, and they do not add input the player did not make. The goal is a wheel that behaves
like the vendor's other supported wheels on the same console.

## Opening a chat with an assistant

> This repo is interoperability and repair work on the owner's own Thrustmaster T150. Read
> `docs/SCOPE.md` and `CLAUDE.md` first. Static analysis, emulation, patching copies, rebuilding pinned
> images, flashing and recovery on the owner's own wheel are in scope. Cite file/address/hash, label
> confidence, and keep the stock image and recovery path with every deployment step.
