#!/bin/bash
set -e

echo zig version $(zig version)
#touch symbols.txt
zig build
echo missing llvm-objdump-6.0
#llvm-objdump-14 --source -disassemble-all -section-headers -t  zig-out/bin/main > main.asm
#grep '^00000000.*:$' main.asm | sed 's/^00000000//' > symbols.txt
#zig build

#ARCH=thumbv6m
#SOURCE=$(ls mission0*.zig)
#llvm-objdump -x --source main > asm.$ARCH
#set +e
#grep unknown asm.$ARCH | grep -v '00 00 00 00'
#grep 'q[0-9].*#' asm.$ARCH | egrep -v '#(-|)(16|32|48|64|80|96|112|128)'
#set -e

# ls -l zig-out/bin/main.img symbols.txt
ls -l zig-out/bin/main.img
