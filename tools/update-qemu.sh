#!/bin/bash
set -e

echo updating qemu-system-arm ...
sudo apt-get update
sudo apt-get install -yq qemu-system-arm
echo
echo qemu installed
qemu-system-arm --version
