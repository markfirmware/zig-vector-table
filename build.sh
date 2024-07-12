#!/bin/bash
set -e

export PATH=tools/zig:$PATH
NAME=main

zig fmt *.zig
zig build-exe -target thumb-freestanding-none -mcpu cortex_m0 --script linker.ld -ffunction-sections $NAME.zig
zig objcopy -O hex $NAME $NAME.hex
