#!/bin/bash
set -e

ZIG=$(wget --quiet --output-document=- https://ziglang.org/download/index.json | jq --raw-output '.master."x86_64-linux".tarball')
echo installing $ZIG
wget --quiet --output-document=- $ZIG | tar Jx
mv zig-linux-x86_64-* zig
cp elf.zig ./zig/lib/zig/std/ # https://github.com/zigling/zig/issues/5270
echo zig version $(./zig/zig version)