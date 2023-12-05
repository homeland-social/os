#!/bin/bash -x

INPUT=$1
OUTPUT=$2

source ${SRC}/${CONFIG}

IMAGE=${OUT}/${OUTPUT}
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
mkfs.ext4 /dev/mapper/${LOOP_NAME}p1
mkfs.ext4 /dev/mapper/${LOOP_NAME}p2
mkfs.ext4 -L DATA /dev/mapper/${LOOP_NAME}p3

# Mount both roots
mkdir -p /tmp/root0
mkdir -p /tmp/root1

if ! mount /dev/mapper/${LOOP_NAME}p1 /tmp/root0; then
    echo Failed to mount root loopback device
    exit 1
fi
if ! mount /dev/mapper/${LOOP_NAME}p2 /tmp/root1; then
    echo Failed to mount backup loopback device
    exit 1
fi

mkdir -p /tmp/root0/data

if ! mount /dev/mapper/${LOOP_NAME}p3 /tmp/root0/data; then
    echo Failed to mount data loopback device
    exit 1
fi

[ ! -z "${HOOK_RUN_BEFORE_TAR}" ] && ${HOOK_RUN_BEFORE_TAR}

# Extract files onto filesystems
cd /tmp/root0 && tar xzf /var/lib/homeland/out/${INPUT}
cd /

sync

# Add bootloader
grub-install --target=i386-pc --boot-directory=/tmp/root0/boot --no-floppy ${LOOP}
cat > /tmp/root0/boot/grub/grub.cfg <<EOF
set timeout=3
set default=0

menuentry "Homeland social [${VERSION}]" {
    set root=(hd0,1)
    linux /boot/vmlinuz-${BOARD_NAME} root=/dev/sda1 ro rootfstype=ext4
    initrd /boot/initramfs-${BOARD_NAME}
}
EOF

[ ! -z "${HOOK_RUN_BEFORE_UMOUNT}" ] && ${HOOK_RUN_BEFORE_UMOUNT}

# Umount and clean up.
for mount in /tmp/root0/data /tmp/root0 /tmp/root1; do
    while ! umount ${mount}; do
        sleep 3.0
    done
done

dd if=/dev/mapper/${LOOP_NAME}p1 of=${OUT}/part-${VERSION}.img bs=4096

kpartx -d -v ${LOOP}
