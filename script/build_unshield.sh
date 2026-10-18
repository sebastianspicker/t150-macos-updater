#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=1.6.2
SHA=a937ef596ad94d16e7ed2c8553ad7be305798dcdcfd65ae60210b1e54ab51a2f
CACHE="$ROOT/.build/third-party"
ARCHIVE="$CACHE/unshield-$VERSION.tar.gz"
SOURCE="$CACHE/unshield-$VERSION"
BUILD="$CACHE/unshield-build"
command -v cmake >/dev/null || { echo 'Install the developer prerequisite: brew install cmake' >&2; exit 1; }
mkdir -p "$CACHE"
if [[ ! -f "$ARCHIVE" ]]; then
    curl --fail --location --proto '=https' --tlsv1.2 \
        "https://github.com/twogood/unshield/archive/refs/tags/$VERSION.tar.gz" -o "$ARCHIVE.download"
    mv "$ARCHIVE.download" "$ARCHIVE"
fi
[[ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" == "$SHA" ]] || { echo 'Unshield source SHA-256 mismatch.' >&2; exit 1; }
# Re-extract the verified archive so an edited cache cannot silently change the tool.
rm -rf "$SOURCE"
tar -xzf "$ARCHIVE" -C "$CACHE"
cmake -S "$SOURCE" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" \
    -DBUILD_STATIC=ON -DUSE_OUR_OWN_MD5=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=TRUE \
    -DCMAKE_EXE_LINKER_FLAGS=-liconv \
    "-DCMAKE_C_FLAGS=-Wno-deprecated-non-prototype -ffile-prefix-map=$ROOT=."
cmake --build "$BUILD" --target unshield --clean-first --parallel
echo "Built $BUILD/src/unshield"
