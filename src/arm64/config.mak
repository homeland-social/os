#!/bin/bash

# See default config below. Variables that can be modified are defined there.
# To append to an option, do:
# FOO="${FOO} your options here"

include ${BUILD_ROOT}/src/default/config.mak

export ARCH=arm64
export BOARD_NAME=rpi4
export NET_ETH=e1000
export PACKAGES_INSTALL="docker-cli docker-bash-completion"
