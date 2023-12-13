#!/bin/sh

# NOTE this runs INSIDE the container.

apk update
apk upgrade
apk add alpine-sdk xorriso parted mkinitfs docker-cli bash tar \
    coreutils e2fsprogs e2fsprogs-extra dosfstools partx sfdisk \
    multipath-tools grub grub-bios grub-efi cloud-utils-growpart \
    btrfs-progs docker-cli-compose #device-mapper

EXEC="$*" make -C /var/lib/homeland/src
