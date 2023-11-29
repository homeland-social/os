#!/bin/bash -x

# Create (2G) disk image
IMAGE=${OUT}/disk.img
dd if=/dev/zero of=${IMAGE} bs=2048 count=1048576

# Find and create loopback device
LOOP=$(losetup -f)
if [ ! "${LOOP}" ]; then
    echo Cannot allocate loopback device
    exit 1
fi
LOOP_NAME=$(basename ${LOOP})
LOOP_NUM=$(echo ${LOOP_NAME} | sed -e s/[^0-9]//g)
if [ ! -b ${LOOP} ]; then
    if ! mknod ${LOOP} b 7 ${LOOP_NUM}; then
        echo Could not create loopback device
        exit 1
    fi
fi

if ! losetup ${LOOP} ${IMAGE}; then
    echo Count not setup loopback device
    exit 1
fi
sfdisk ${LOOP} < ${SRC}/${ARCH}/partitions.sfdisk
losetup -d ${LOOP}
if ! kpartx -a -v ${IMAGE}; then
    echo Could not create partition devices
    exit 1
fi

# Format partitions
mkfs.vfat /dev/mapper/${LOOP_NAME}p1
mkfs.ext4 /dev/mapper/${LOOP_NAME}p2
mkfs.ext4 /dev/mapper/${LOOP_NAME}p3
mkfs.ext4 /dev/mapper/${LOOP_NAME}p4

# Mount boot and root
mkdir -p /tmp/boot
mkdir -p /tmp/root0
mkdir -p /tmp/root1
mkdir -p /tmp/data

if ! mount /dev/mapper/${LOOP_NAME}p1 /tmp/boot; then
    echo Failed to mount boot loopback device
    exit 1
fi
if ! mount /dev/mapper/${LOOP_NAME}p2 /tmp/root0; then
    echo Failed to mount root0 loopback device
    exit 1
fi
if ! mount /dev/mapper/${LOOP_NAME}p3 /tmp/root1; then
    echo Failed to mount root1 loopback device
    exit 1
fi
if ! mount /dev/mapper/${LOOP_NAME}p4 /tmp/data; then
    echo Failed to mount data loopback device
    exit 1
fi

# Extract files onto filesystems
cd /tmp/boot && tar xzf /var/lib/homeland/out/bootfs.tar.gz
cd /tmp/root0 && tar xzf /var/lib/homeland/out/rootfs.tar.gz
cd /tmp/root1 && tar xzf /var/lib/homeland/out/rootfs.tar.gz
cd /

mkdir -p /tmp/data/var/overlay_/var/lib/docker

sync

# Add bootloader
grub-install --target=i386-pc --boot-directory=/tmp/boot --no-floppy ${LOOP}
cat <<EOF > /tmp/boot/grub/grub.cfg
set timeout=3
set default=0

menuentry "Homeland social" {
    set root=(hd0,1)
    linux /vmlinuz-virt root=/dev/sda2 rootfstype=ext4
    initrd /initramfs-virt
}
EOF

# NOTE: manhole -- comment out following line if not needed
/bin/bash

# Umount and clean up.
while ! umount /tmp/boot; do
    sleep 3.0
done
while ! umount /tmp/root0; do
    sleep 3.0
done
while ! umount /tmp/root1; do
    sleep 3.0
done

kpartx -d -v ${LOOP}
