#!/bin/bash

NAME=main

set -e
./build.sh
set +e
qemu-system-arm -M microbit -device loader,file=$NAME.hex -serial stdio -display none
reset
