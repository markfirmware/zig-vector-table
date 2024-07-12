#!/bin/bash
set -ex

ZIGVER=0.13.0

cd tools/
rm -rf zig/

echo installing zig $ZIGVER
ZIG=$(wget --quiet --output-document=- https://ziglang.org/download/index.json | jq --raw-output ".\"$ZIGVER\".\"x86_64-linux\"".tarball)
wget --quiet --output-document=- $ZIG | tar Jx
mv zig-linux-x86_64-* zig
echo zig version $(./zig/zig version)

exit 0
