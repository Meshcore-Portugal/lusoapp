#!/bin/bash
set -euo pipefail

FLUTTER_VERSION="3.41.6-stable"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}.tar.xz"
[ -d ~/sdk ] || mkdir ~/sdk
curl -sSL ${FLUTTER_URL} | tar -xJf - -C ~/sdk

echo 'export PATH="${HOME}/sdk/flutter/bin:$PATH"' >> ~/.bashrc
${HOME}/sdk/flutter/bin/dart --disable-analytics
${HOME}/sdk/flutter/bin/flutter --disable-analytics

if [ -x /usr/bin/ar ] && [ ! -e /usr/lib/llvm-14/bin/ar ]; then
	sudo ln -snf /usr/bin/ar /usr/lib/llvm-14/bin/ar
fi

if [ -x /usr/lib/llvm-14/bin/llvm-ar ] && [ ! -e /usr/local/bin/llvm-ar ]; then
	sudo ln -snf /usr/lib/llvm-14/bin/llvm-ar /usr/local/bin/llvm-ar
fi

if [ -x /usr/lib/llvm-14/bin/ld.lld ] && [ ! -e /usr/local/bin/ld.lld ]; then
	sudo ln -snf /usr/lib/llvm-14/bin/ld.lld /usr/local/bin/ld.lld
fi