#!/bin/bash -x

INPUT=$1
OUTPUT=$2

IMAGE=${OUT}/${OUTPUT}
dd if=/dev/zero of="${IMAGE}" bs="${DISK_SIZE}" count=1048576

# Find and create loopback device
LOOP=$(losetup -f)
if [ ! "${LOOP}" ]; then
    echo Cannot allocate loopback device
    exit 1
fi
LOOP_NAME=$(basename "${LOOP}")
LOOP_NUM=$(echo "${LOOP_NAME}" | sed -e s/[^0-9]//g)
if [ ! -b "${LOOP}" ]; then
    if ! mknod "${LOOP}" b 7 "${LOOP_NUM}"; then
        echo Could not create loopback device
        exit 1
    fi
fi

echo Set up "${LOOP}"...

if ! losetup "${LOOP}" "${IMAGE}"; then
    echo Count not setup loopback device
    exit 1
fi

[ ! -z "${HOOK_RUN_AFTER_LOSETUP}" ] && ${HOOK_RUN_AFTER_LOSETUP}

# Create partitions
DATA_END=$((BOOT_SIZE + (ROOT_SIZE * 2) + 3))
if [ ! -z "${DATA_SIZE}" ]; then
    DATA_END=$((DATA_END + DATA_SIZE))
else
    DATA_END=$((DATA_END + 1))
fi
parted -s "${LOOP}" unit MiB mklabel msdos \
    mkpart primary ext4 1 $((BOOT_SIZE + 1)) \
    mkpart primary ext4 $((BOOT_SIZE + 1))  $((BOOT_SIZE + ROOT_SIZE + 2)) \
    mkpart primary ext4 $((BOOT_SIZE + ROOT_SIZE + 2)) $((BOOT_SIZE + (ROOT_SIZE * 2) + 3)) \
    mkpart primary ext4 $((BOOT_SIZE + (ROOT_SIZE * 2) + 3)) ${DATA_END}

if [ -z "${DATA_SIZE}" ]; then
    growpart "${LOOP}" 4
fi
sfdisk -d "${LOOP}"

losetup -d "${LOOP}"
while losetup -a | grep "${LOOP}"; do
    sleep 0.1
done

if ! kpartx -a -v "${IMAGE}"; then
    echo Could not create partition devices
    exit 1
fi

# Format partitions
mkfs.ext4 "/dev/mapper/${LOOP_NAME}p1"
mkfs.ext4 "/dev/mapper/${LOOP_NAME}p2"
mkfs.ext4 "/dev/mapper/${LOOP_NAME}p3"
mkfs.ext4 -L DATA "/dev/mapper/${LOOP_NAME}p4"

# Mount both roots
mkdir -p /tmp/root0
mkdir -p /tmp/root1

if ! mount "/dev/mapper/${LOOP_NAME}p2" /tmp/root0; then
    echo Failed to mount root loopback device
    exit 1
fi
if ! mount "/dev/mapper/${LOOP_NAME}p3" /tmp/root1; then
    echo Failed to mount backup loopback device
    exit 1
fi

mkdir -p /tmp/root0/data
mkdir -p /tmp/root0/boot

if ! mount "/dev/mapper/${LOOP_NAME}p4" /tmp/root0/data; then
    echo Failed to mount data loopback device
    exit 1
fi
if ! mount "/dev/mapper/${LOOP_NAME}p1" /tmp/root0/boot; then
    echo Failed to mount boot loopback device
    exit 1
fi

[ ! -z "${HOOK_RUN_BEFORE_TAR}" ] && ${HOOK_RUN_BEFORE_TAR}

# Extract files onto filesystems
cd /tmp/root0 && tar xzf "/var/lib/homeland/out/${INPUT}" > /dev/null 2>&1
cd /

sync

# Add bootloader
grub-install --target=i386-pc --boot-directory=/tmp/root0/boot --no-floppy "${LOOP}"
if [ $? != 0 ]; then
    echo Failed to install bootloader
    exit 1
fi

cat > /tmp/root0/boot/grub/grub.cfg <<EOF
set timeout=3
set default=0

menuentry "Homeland social [${VERSION}]" {
    set root=(hd0,1)
    linux /boot/vmlinuz-${BOARD_NAME} root=/dev/sda2 ro rootfstype=ext4
    initrd /boot/initramfs-${BOARD_NAME}
}
EOF

[ ! -z "${HOOK_RUN_BEFORE_UMOUNT}" ] && ${HOOK_RUN_BEFORE_UMOUNT}

# Umount and clean up.
for mount in /tmp/root0/boot /tmp/root0/data /tmp/root0 /tmp/root1; do
    while ! umount ${mount}; do
        sleep 3.0
    done
done

dd if="/dev/mapper/${LOOP_NAME}p2" of="${OUT}/part-${BOARD_NAME}-${ARCH}-${VERSION}.img" bs=4096

kpartx -d -v "${LOOP}"
