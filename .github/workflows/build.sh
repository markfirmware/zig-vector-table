#!/bin/bash
set -e

echo zig version $(zig version)
zig build
ls -lt zig-cache/bin/main
