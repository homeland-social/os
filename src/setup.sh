#!/bin/sh

apk update
apk upgrade
apk add alpine-sdk xorriso parted mkinitfs docker-cli bash tar \
    coreutils e2fsprogs e2fsprogs-extra dosfstools partx sfdisk \
    multipath-tools grub grub-bios grub-efi cloud-utils-growpart
./$@