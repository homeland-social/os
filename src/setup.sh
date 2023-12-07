#!/bin/sh

apk update
apk upgrade
apk add alpine-sdk xorriso sfdisk mkinitfs docker-cli bash tar \
    coreutils e2fsprogs e2fsprogs-extra dosfstools partx \
    multipath-tools grub grub-bios grub-efi

./$@
