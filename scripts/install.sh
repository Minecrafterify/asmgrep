#!/bin/sh
# Installs asmgrep. Usage: scripts/install.sh [PREFIX]
# Without an argument the prefix is /usr when run as root and ~/.local otherwise.
set -eu

cd "$(dirname "$0")/.."
if [ "$#" -ge 1 ]; then
    prefix=$1
elif [ "$(id -u)" = 0 ]; then
    prefix=/usr
else
    prefix=$HOME/.local
fi

make PREFIX="$prefix"
make install PREFIX="$prefix"

if [ "$prefix" != /usr ] && [ "$prefix" != /usr/local ]; then
    cat <<MSG

Installed under $prefix. Make sure the following are set in your shell profile:
  export PATH="$prefix/bin:\$PATH"
  export LD_LIBRARY_PATH="$prefix/lib:\${LD_LIBRARY_PATH:-}"
MSG
fi
