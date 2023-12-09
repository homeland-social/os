# See default config below. Variables that can be modified are defined there.
# To append to an option, do:
# FOO="${FOO} your options here"

include ${BUILD_ROOT}/src/default/config.mak

# Sizes in Megabytes, leave DATA_SIZE blank to grow
export DISK_SIZE=16384
export BOOT_SIZE=128
export ROOT_SIZE=6144
export DATA_SIZE=

export BOARD_NAME=lts
export NET_WIFI=yes
export NET_ETH=e1000
export PACKAGES_INSTALL=docker-cli docker-bash-completion usbutils go alpine-sdk nfs-utils nodejs
export MODULES_LOAD=rt2800usb
