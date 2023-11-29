#!/bin/bash -x

source ${SRC}/config

# Create (2G) disk image
IMAGE=${OUT}/disk.img
dd if=/dev/zero of=${IMAGE} bs=3084 count=1048576

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

echo Set up ${LOOP}...

if ! losetup ${LOOP} ${IMAGE}; then
    echo Count not setup loopback device
    exit 1
fi

[ ! -z "${HOOK_RUN_AFTER_LOSETUP}" ] && ${HOOK_RUN_AFTER_LOSETUP}

# Create partitions
if [ -f ${SRC}/${ARCH}/partitions.sfdisk ]; then
    sfdisk ${LOOP} < ${SRC}/${ARCH}/partitions.sfdisk
fi

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
mkdir -p /tmp/root0
mkdir -p /tmp/root1

if ! mount /dev/mapper/${LOOP_NAME}p2 /tmp/root0; then
    echo Failed to mount root loopback device
    exit 1
fi
if ! mount /dev/mapper/${LOOP_NAME}p3 /tmp/root1; then
    echo Failed to mount backup loopback device
    exit 1
fi

mkdir -p /tmp/root0/boot
mkdir -p /tmp/root0/data

if ! mount /dev/mapper/${LOOP_NAME}p1 /tmp/root0/boot; then
    echo Failed to mount boot loopback device
    exit 1
fi
if ! mount /dev/mapper/${LOOP_NAME}p4 /tmp/root0/data; then
    echo Failed to mount data loopback device
    exit 1
fi

# Extract files onto filesystems
cd /tmp/root0 && tar xzf /var/lib/homeland/out/rootfs.tar.gz
cd /tmp/root1 && tar --exclude="data/*" --exclude="boot/*" -xzf /var/lib/homeland/out/rootfs.tar.gz
cd /

mkdir -p /tmp/root0/data/overlay_/var/lib/docker
mkdir -p /tmp/root0/data/work_/var/lib/docker
mkdir -p /tmp/root0/data/links_/etc/network

sync

# Add bootloader
grub-install --target=i386-pc --boot-directory=/tmp/root0/boot --no-floppy ${LOOP}
cat > /tmp/root0/boot/grub/grub.cfg <<"EOF"
set timeout=3
set default=0

menuentry "Homeland social" {
    set root=(hd0,1)
    linux /vmlinuz-${BOARD_NAME} root=/dev/sda2 rootfstype=ext4
    initrd /initramfs-${BOARD_NAME}
}
EOF

# NOTE: manhole -- comment out following line if not needed
/bin/bash

# Umount and clean up.
for mount in /tmp/root0/boot /tmp/root0/data /tmp/root0 /tmp/root1; do
    while ! umount ${mount}; do
        sleep 3.0
    done
done

kpartx -d -v ${LOOP}
