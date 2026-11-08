#!/bin/sh
set -eu
native_root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$native_root/build"
xcrun clang -std=c11 -Wall -Wextra -Werror -Wno-deprecated-declarations \
  -mmacosx-version-min=14.0 -framework IOKit -framework CoreFoundation \
  "$native_root/t150_engine.c" -o "$native_root/build/t150-engine"
