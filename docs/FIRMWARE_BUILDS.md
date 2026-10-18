# Firmware builds

The app can install seven builds of T150 firmware V35. The first is Thrustmaster's
official image. The other six are that image with a reviewed set of bytes
replaced. This page explains what each build changes, why, and what is known
about how it behaves on a PlayStation 5.

None of these builds is an official Thrustmaster release.

## How the modified builds are made

No modified firmware is shipped with the app or downloaded. The native engine
builds each one on your Mac:

1. It decodes the official V35 image from the installer you selected and checks
   it against a pinned SHA-256.
2. It applies the build's compiled patch table from `Native/policy.inc`. Each
   entry replaces at most 8 bytes, and the engine checks that the original bytes
   are what it expects. Entries may only touch the application region
   (`0x2000` to `0xfff7`). Larger changes live in erased flash at the end of the
   application and are reached through short branch instructions.
3. It recomputes the footer checksum and compares the complete 64 KiB image with
   the build's pinned SHA-256. Any difference stops the update before a write.

The bootloader (`0x0000` to `0x1fff`) is never changed, and the version word stays
35. Because of that, the app can always switch back. A V35 wheel can move between
any two of the seven builds in either direction, as long as its flash holds
exactly one of them. Any other V35 image is refused.

## Overview

| Name in the app | Full name | Engine profile | Patch entries | Console status |
| --- | --- | --- | --- | --- |
| Official V35 | Official V35 | `t150-v35-boot5` | 0 | Stutters in ACC on PS5 |
| V35 + fixes | V35 + fixes | `t150-v35-fixes-boot5` | 26 | No console change expected |
| **PS5 stutter fix** | V35 + sibling mimic + T300 features + recorder | `t150-v35-sibrec-feat-boot5` | 368 | **Fixed the stutter (tester's T150, several races)** |
| PS5 stutter patch (first attempt) | V35 + fixes + PS5 stutter patch | `t150-v35-full-boot5` | 122 | Did not change the stutter (earlier tester report) |
| Sibling mimic | V35 + sibling mimic + recorder | `t150-v35-sibrec-boot5` | 329 | Not tried on a console |
| Sibling mimic + RAW keepalive | V35 + sibling mimic + recorder + RAW keepalive | `t150-v35-sibrec-raw-boot5` | 345 | Not tried on a console |
| PS5 stutter fix + RAW keepalive | V35 + sibling mimic + T300 features + recorder + RAW keepalive | `t150-v35-sibrec-feat-raw-boot5` | 384 | Not tried on a console |

The PS5 stutter fix is the build to use. The last four are kept for completeness
and further testing; the app lists them under "Other experimental builds",
collapsed. All five experimental builds need two separate acknowledgements before
the app offers the backup and update steps.

Pinned full-image SHA-256 values:

```text
37a481796e85d05cf75bafc56bea73fb647b0cfc63270dbb3761d699ee6c5056  official
7822b9095ee0ebdf466d7a8cbc4bf1fb332521fac89cefd87a63963e8ac03f34  fixes
a4444a06ce5a7dcd5e2afaeab76015b588ee55548613ccb17fc8f3148c29509b  full (PS5 stutter patch)
6874dd15c981581325396fe6e595fe46ed73c79b1ae1b9a19f3a7685ff60f9a9  sibrec
e921b91ee581809c2e138be7706864df608efd69e463f1ccde1db206766f6886  sibrec-feat
1e2de4a320788b58ade80b68a3c9c1c32582588343f13df52bd06d61d733128a  sibrec-raw
e934f1e6ce741eab4a0e0e0ed24392348310e70732b251a5fb079ae081932005  sibrec-feat-raw
```

## V35 + fixes

Defects found by disassembling V35 and reproducing each one in an emulator.

| Id | Defect in official V35 | What a user can notice | Fix |
| --- | --- | --- | --- |
| D1 | Three settings writers check the EEPROM log for "full" at the wrong size, so the log can run past its 1 KiB. The next write then fails and the firmware loops forever. | The wheel stops working after many setting changes. | Compare at the real log size, so the log is compacted in time. |
| D3 | A HID SET_REPORT(Output) over the control endpoint copies any amount of data into an unused buffer, then replays the previous force-feedback command. | Random force-feedback replays. A large request hangs the USB interrupt. | Acknowledge the request without copying or replaying. |
| D4 | The control endpoint's data stage accepts any length into a 64-byte buffer. | Memory corruption from a malformed request. | Reject requests longer than 64 bytes. |
| D5 | The brown-out interrupt points at an endless loop. | The wheel hangs after a power dip instead of restarting. | Restart the wheel. |
| D7 | Force-feedback effect writes use a host-supplied offset without checking it. A DualShock-style output report is enough to corrupt effects. | Wrong or broken force-feedback effects, crashes. | Bound the offsets to the effect pool. |
| D8 | Two force-feedback opcodes copy memory between host-supplied addresses. | Crashes, reads of arbitrary memory. | Treat them as handled without copying. |

D2 and D6 were suspected too, but they do not reproduce, so they are not patched.

## V35 + fixes + PS5 stutter patch

The first attempt at the ACC PS5 stutter. It contains everything in V35 + fixes,
plus:

| Id | Change | Reason |
| --- | --- | --- |
| D9 | Incoming force-feedback packets go into a 4-slot queue. | Official V35 keeps a single buffer, so a burst of commands overwrites earlier ones before they are parsed. |
| D10 | GET_REPORT(Input) returns the current input report. | Official V35 returns whatever the buffer last held. |
| D11 | Setting the rotation range writes EEPROM only when the value changed. | Avoids needless EEPROM writes and the stalls they cause. |
| D12 | A USB transfer that is still pending is cancelled before the endpoint is reused. | Official V35 can overwrite an active transfer, which can hand the host a torn packet. |
| P4 | The PlayStation input report carries a DualShock-style frame counter and timestamp. | Guess at the time: the console might pace input by these fields. |
| P5 | Small pedal noise no longer produces new input reports in PlayStation mode. | With a pedal partly pressed, one count of sensor noise produced a report every 5 ms. |

In an earlier tester report this build did not change the stutter. D9 to D12 are
still real fixes and are kept in the later builds. P4 and P5 were removed again,
because Thrustmaster's own T300 and T248 firmware do neither (see below).

## Sibling mimic builds

These builds start from the PS5 stutter patch without P4 and P5. They then make
the T150 answer the console the way the T300 RS does.

**B1, 64-byte console replies (all four builds).** In PlayStation mode the T150
sends its vendor replies and range-status packets as 15-byte packets. The T300 and
T248 send 64 bytes. B1 pads these packets to 64 bytes with zeros. Input reports
and PC modes are unchanged.

**B2, T300 feature reports (the two "T300 features" builds).** In PlayStation mode
only:

| Feature report | Official T150 | With B2 |
| --- | --- | --- |
| 0x03 (capabilities) | T150 values in bytes 3, 24, 27 and 32 | the T300's values |
| 0x4a | T150 encoding in bytes 2 and 6, byte 7 = 3 | the T300's encoding, byte 7 = 2 |
| 0x49 (on a T300: rim, rotation range, status) | rejected with a STALL | answered with the T300 layout |

The wheel's identity reply is unchanged, so a game still sees a T150.

**B4, RAW keepalive (the two "RAW keepalive" builds).** On a T300, the vendor
command `RAW` also sets the input keepalive to 8 ms, so the wheel sends at least
125 reports per second. `NORM` sets it back to 250 ms. The T150 ignores the timing
part. B4 copies the T300 behaviour, in PlayStation mode only.

**Recorder (all four builds).** In PlayStation mode the firmware counts what the
console sends: control requests, force-feedback opcodes with timing, vendor
commands, and the replies B1 padded. It changes nothing the wheel sends. Once per
power-on, when the PS/PC switch is flipped while the wheel runs or when the
console suspends USB, it saves the counts as one 1 KiB record in a separate EEPROM
area (`0x800` to `0xbff`). Wheel settings live elsewhere and are not touched. The
tool that reads the record is not part of this repository.

## The ACC PS5 stutter

### Symptom

In the native PS5 version of Assetto Corsa Competizione, the whole game stutters
with a T150. It gets worse with force feedback above about 30 % and with wheel
movement, and it does not go away at 0 % force feedback. The PS4 version of ACC on
the same console runs fine with the same wheel.

### What was ruled out

- **The wheel making the console wait.** Control requests are answered inside
  the USB interrupt, force-feedback data is always accepted, and input reports
  never block. Proven by disassembly and emulation.
- **The input stream.** The T300 RS (including its "PS5 mode") and the T248, which
  was made for the PS5, present the same USB identity, a byte-identical HID
  report descriptor, and the same input stream: reports only on change plus a
  250 ms keepalive, with no frame counter or timestamp. Their "PS5 mode" only
  changes an LED or a display text. So the T150's stream is normal for a
  Thrustmaster console wheel, and P4/P5 made the T150 less like its siblings.
  This fits the PS5 stutter patch not helping.

### What fixed it

The PS5 stutter fix ("V35 + sibling mimic + T300 features + recorder") removed the
stutter on a tester's T150. The owner drove several ACC races on the PS5 without stutter, with the wheel
fully working in the game. That is one owner's report on one wheel, without
frame-time or USB measurements.

### Why it works

Compare the build that works with the ones that do not:

| | Official | PS5 stutter patch | T300 features build |
| --- | --- | --- | --- |
| Fixes D1 to D12 | no | yes | yes |
| Input stream | official | changed (P4, P5) | official |
| Console replies and feature reports | T150 | T150 | T300 (B1, B2) |
| Recorder | no | no | yes, passive |
| Stutter | yes | yes | **no** |

The fixes alone did not help, and the official input stream stutters. The
recorder only counts and never changes what the wheel sends. That leaves B1, B2
or both as the fix. Both only change answers to requests the console has to make,
so the PS5 version of ACC must send at least one of these requests while it runs.

How the original answers cause a stall is not known, but two explanations fit:

- **Short vendor replies (B1).** Vendor replies and input reports share the same
  USB endpoint. Every other Thrustmaster console wheel sends 64-byte packets there.
  A console driver or game that expects a full 64-byte reply could treat the
  T150's 15-byte packet as an error, then wait or retry.
- **Rejected feature report 0x49 (B2).** On a T300, 0x49 reports rim, rotation
  range and status. The official T150 rejects it. A game that asks for it, for
  example after a force-feedback or range change, gets an error every time. A
  control request that fails and is retried on the game's input thread would
  show up as a hitch.

Either would fit ACC's console patch 1.9.1 (July 2023), which fixed "an issue
while driving using the T150 Thrustmaster wheel causes the title to freeze
intermittently"
([505 Games patch notes](https://support.505games.com/support/solutions/articles/150000146834-assetto-corsa-competizione-xsx-ps5-v1-9-1-patch-notes-2023-july-6-)).
So the game has T150-specific code that can block.

Still open:

- whether B1, B2, or both are needed
- why more force feedback and more wheel movement made the stutter worse
- why the PS4 version of ACC is not affected, presumably because it uses an
  older wheel path that never makes these requests

A recorder record from the working build would answer the first point: it shows
which vendor commands and feature requests the PS5 sends. A session with
"V35 + sibling mimic + recorder" (B1 without B2) would answer it too.

### Possible side effects

Feature report 0x03 now carries T300 capability values. Because the identity reply
still says T150, ACC should keep its T150 force-feedback settings. The tester
reports the wheel working normally, but force strength was not compared with the
official firmware.

## How the builds were checked

- **Static review:** every patch site, the original bytes at it, and every branch
  into and out of the added code. No change outside the declared ranges, the
  bootloader identical, and the checksums valid.
- **Emulator:** each build boots in an emulator of the wheel's microcontroller.
  Scripted USB traffic shows each defect in the official image and its absence in
  the patched one, and confirms the rest of the behaviour is unchanged.
- **Engine tests:** with real firmware fixtures, the engine builds each pinned
  image from the official one and from every other build, reverts to each, and
  refuses tampered or partial images. See [DEVELOPMENT.md](DEVELOPMENT.md).

The disassembly, emulator harness and patch sources are not part of this
repository, because they contain Thrustmaster's firmware. The engine's patch
tables show exactly which bytes each build changes.
