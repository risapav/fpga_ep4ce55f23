#!/bin/bash
# scripts/build.sh

set -e

echo "==> Building Quartus project..."
quartus_sh --tcl_script scripts/build.tcl

echo "==> Done."
