# Third-party notices

The app bundles **Unshield 1.6.2**, built from the unchanged tagged source with a
static libunshield, `USE_OUR_OWN_MD5=ON`, and OpenSSL discovery disabled. It reads
InstallShield cabinets; it does not execute the selected Windows installer.

- Source: https://github.com/twogood/unshield/tree/1.6.2
- Archive: https://github.com/twogood/unshield/archive/refs/tags/1.6.2.tar.gz
- Archive SHA-256: `a937ef596ad94d16e7ed2c8553ad7be305798dcdcfd65ae60210b1e54ab51a2f`
- [Unshield MIT license](licenses/unshield-MIT.txt).
- Its MD5 implementation is derived from the **RSA Data Security, Inc. MD5
  Message-Digest Algorithm**. The complete [RSA notice](licenses/RSA-MD5.txt)
  accompanies the binary. This legacy checksum is used by the cabinet reader;
  the updater's reviewed artifact identities use SHA-256.

Unshield links to macOS-supplied libz, libiconv, and libSystem. Those OS libraries
are not copied into the app. No OpenSSL, 7-Zip, Wine, VM, Windows driver, vendor
updater, or firmware is distributed. The project independently implements the
native transport and importer; vendor names identify compatible products and do
not imply endorsement.

## Thrustmaster firmware

No Thrustmaster installer, driver or firmware image is included in this
repository or in the app. Users download the official installer themselves. The
patch tables in `Native/policy.inc` contain short fragments of the original V35
firmware bytes so the engine can confirm it is patching the right image. Those
fragments remain Thrustmaster's property and are not covered by this project's
MIT License.

`script/build_unshield.sh` is the corresponding build recipe. The built app
includes these notices under `Contents/Resources/ThirdPartyNotices`.
