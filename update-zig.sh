#!/bin/bash
set -e

rm -rf zig/ zls/

ZIG=$(wget --quiet --output-document=- https://ziglang.org/download/index.json | jq --raw-output '.master."x86_64-linux".tarball')
echo installing $ZIG into ./zig/
wget --quiet --output-document=- $ZIG | tar Jx
mv zig-linux-x86_64-* zig
echo zig version $(./zig/zig version)

git clone --recurse-submodules https://github.com/zigtools/zls
cd zls
set +e
../zig/zig build -Ddata_version=master
exit 0
