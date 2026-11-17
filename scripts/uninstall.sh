#!/bin/sh
# Removes asmgrep. Usage: scripts/uninstall.sh [PREFIX]
set -eu

cd "$(dirname "$0")/.."
if [ "$#" -ge 1 ]; then
    prefix=$1
elif [ "$(id -u)" = 0 ]; then
    prefix=/usr
else
    prefix=$HOME/.local
fi

make uninstall PREFIX="$prefix"
