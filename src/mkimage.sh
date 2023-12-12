#!/bin/bash -x

OUTPUT=$1

MODULES_LOAD="${MODULES_LOAD} ${NET_ETH}"
PACKAGES_INSTALL="${PACKAGES_INSTALL} docker-engine alpine-base grub linux-${BOARD_NAME} cloud-utils-growpart e2fsprogs e2fsprogs-extra"
SERVICES_ENABLE="${SERVICES_ENABLE} networking modules docker expand-data sysctl"

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
mkfs.btrfs -L DATA "/dev/mapper/${LOOP_NAME}p4"

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

ROOT=/tmp/root0
mkdir -p ${ROOT}
mkdir -p ${ROOT}/etc/apk
cp -R /etc/apk ${ROOT}/etc/

[ ! -z "${HOOK_RUN_BEFORE_TAR}" ] && ${HOOK_RUN_BEFORE_TAR}

# Extract files onto filesystems

apk add -U \
    -X "${ALPINE_MIRROR}v${ALPINE_VERSION}/main" \
    -X "${ALPINE_MIRROR}v${ALPINE_VERSION}/community" \
    --no-cache --allow-untrusted --initdb -p ${ROOT} ${PACKAGES_INSTALL}

[ ! -z "${HOOK_RUN_AFTER_APK}" ] && ${HOOK_RUN_AFTER_APK}

mkdir -p ${ROOT}/dev
mkdir -p ${ROOT}/proc
mkdir -p ${ROOT}/sys
mkdir -p ${ROOT}/var/lib/homeland/

mount -o bind /dev ${ROOT}/dev
mount -o bind /proc ${ROOT}/proc
mount -o bind /sys ${ROOT}/sys
mount -o bind /sys/fs/cgroup ${ROOT}/sys/fs/cgroup
mount -o bind /tmp ${ROOT}/tmp

# Create r/w mount point
mkdir -p ${ROOT}/data

cp "${DOCKER_CONFD_PATH}" ${ROOT}/etc/conf.d/docker
cp "${CONTAINERS_INITD_PATH}" ${ROOT}/etc/init.d/containers
cp "${EXPAND_DATA_CONFD_PATH}" ${ROOT}/etc/conf.d/expand-data
cp "${EXPAND_DATA_INITD_PATH}" ${ROOT}/etc/init.d/expand-data
chmod +x ${ROOT}/etc/init.d/containers
chmod +x ${ROOT}/etc/init.d/expand-data

# This will be useful
if [ -f "${RESOLV_CONF_PATH}" ]; then
    cp "${RESOLV_CONF_PATH}" ${ROOT}/etc/resolv.conf
else
    echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4\n" > ${ROOT}/etc/resolv.conf
fi
mkdir -p ${ROOT}/etc/udhcpc
echo 'RESOLV_CONF="NO"' > ${ROOT}/etc/udhcpc/udhcpc.conf

# Append to /etc files
[ -f "${FSTAB_APPEND_PATH}" ] && cat "${FSTAB_APPEND_PATH}" >> ${ROOT}/etc/fstab

# Append modules for auto-loading
for mod in ${MODULES_LOAD}; do
    echo "${mod}" >> ${ROOT}/etc/modules
done

if [ ! -z "${NET_ETH}" ]; then
    # Set up networking (and symlink allowing /etc/network/interfaces to be writable)
    mkdir -p ${ROOT}/data/etc/network
    echo homeland > ${ROOT}/etc/hostname
    cat > ${ROOT}/data/etc/network/interfaces <<EOF
auto lo
auto eth0
iface lo inet loopback
iface eth0 inet dhcp
EOF
    cd ${ROOT}/etc/network && ln -sf /data/etc/network/interfaces interfaces
fi

echo "VERSION=\"${VERSION}\"" > ${ROOT}/etc/release
echo "ARCH=\"${ARCH}\"" >> ${ROOT}/etc/release
echo kernel.printk = 2 4 1 7 > ${ROOT}/etc/sysctl.d/local.conf

# NOTE: this is fixed in alpine 3.19:
# https://github.com/alpinelinux/aports/commit/3a8f76ba962aca7c4553f3dd138ba5b0edabcb2e
chroot ${ROOT} /usr/sbin/addgroup -S docker 2> /dev/null
chroot ${ROOT} mkdir -p /data//var/lib/docker

[ ! -z "${HOOK_RUN_AFTER_FILES}" ] && ${HOOK_RUN_AFTER_FILES}

if [ ! -z "${DOCKER_PULL}" ]; then
    SOCK="/tmp/docker.sock"
    SERVICES_ENABLE="${SERVICES_ENABLE} containers"

    # Run dockerd inside the chroot.
    chroot ${ROOT} /usr/bin/dockerd --storage-driver=btrfs \
        -H unix://${SOCK} --pidfile=/tmp/docker.pid \
        --data-root=/data/var/lib/docker &

    # Wait for dockerd to start...
    while [ ! -f ${ROOT}/tmp/docker.pid ]; do
        sleep 0.1
    done
    PID=$(cat ${ROOT}/tmp/docker.pid)

    # Pull images and build default manifest...
    echo > /tmp/containers.manifest
    for image_tag in ${DOCKER_PULL}; do
        docker -H unix://${ROOT}${SOCK} pull "${image_tag}"
        echo "${image_tag}" >> /tmp/containers.manifest
    done

    # Use manifest provided in src, otherwise use the default one we generated
    # in the previous step.
    if [ -f "${CONTAINERS_MANIFEST_PATH}" ]; then
        cp "${CONTAINERS_MANIFEST_PATH}" ${ROOT}/etc/containers.manifest
    else
        cp /tmp/containers.manifest ${ROOT}/etc/containers.manifest
    fi

    docker -H unix://${ROOT}${SOCK} image ls

    # Kill dockerd and wait for it to exit.
    kill "${PID}" > /dev/null 2>&1
    while kill -0 "${PID}" > /dev/null 2>&1; do
        sleep 0.1
    done

    # Remove some unnecessary directories
    rm -rf ${ROOT}/var/lib/docker/runtimes ${ROOT}/var/lib/docker/tmp ${ROOT}/run/*
fi

# Enable services
for service in ${SERVICES_ENABLE}; do
    chroot ${ROOT} /sbin/rc-update add "${service}"
done

sync

# Add bootloader
grub-install --target=i386-pc --boot-directory=${ROOT}/boot --no-floppy "${LOOP}"
if [ $? != 0 ]; then
    echo Failed to install bootloader
    exit 1
fi

cat > ${ROOT}/boot/grub/grub.cfg <<EOF
set timeout=3
set default=0

menuentry "Homeland social [${VERSION}]" {
    set root=(hd0,1)
    linux /boot/vmlinuz-${BOARD_NAME} root=/dev/sda2 ro rootfstype=ext4
    initrd /boot/initramfs-${BOARD_NAME}
}
EOF

[ ! -z "${HOOK_RUN_BEFORE_UMOUNT}" ] && ${HOOK_RUN_BEFORE_UMOUNT}

cd /

umount ${ROOT}/dev
umount ${ROOT}/proc
umount ${ROOT}/sys/fs/cgroup
umount ${ROOT}/sys
umount ${ROOT}/tmp

# Umount and clean up.
for mount in /tmp/root0/boot /tmp/root0/data /tmp/root0 /tmp/root1; do
    while ! umount ${mount}; do
        sleep 3.0
    done
done

dd if="/dev/mapper/${LOOP_NAME}p2" of="${OUT}/part-${BOARD_NAME}-${ARCH}-${VERSION}.img" bs=4096

kpartx -d -v "${LOOP}"
