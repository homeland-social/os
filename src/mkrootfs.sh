#!/bin/bash -x

source ${SRC}/config

PACKAGES_INSTALL = "${PACKAGES_INSTALL} alpine-base grub linux-${BOARD_NAME}"
SERVICES_ENABLE = "${SERVICES_ENABLE} networking modules"

if [ "NET_WIFI" == "yes" ]; then
    PACKAGES_INSTALL = "${PACKAGES_INSTALL} iwd"
    SERVICES_ENABLE = "${SERVICES_ENABLE} iwd"
fi

ROOT=/tmp/root
mkdir -p ${ROOT}

apk add -U -X ${ALPINE_MIRROR}v${ALPINE_VERSION}/main \
    -X ${ALPINE_MIRROR}v${ALPINE_VERSION}/community \
    --no-cache --allow-untrusted --initdb -p ${ROOT} ${PACKAGES_INSTALL}
apk del --no-cache -p ${ROOT} --force-broken-world apk-tools

mkdir -p ${ROOT}/var/lib/homeland/
mkdir -p ${ROOT}/data/links_/etc/networking/
cp ${SRC}/${ARCH}/container.manifest ${ROOT}/var/lib/homeland/

mount -o bind /dev ${ROOT}/dev
mount -o bind /proc ${ROOT}/proc
mount -o bind /tmp ${ROOT}/tmp

# Create r/w mount point
mkdir -p ${ROOT}/data

# This will be useful
if [ -f ${SRC}/${ARCH}/resolv.conf ]; then
    cp ${SRC}/${ARCH}/resolv.conf ${ROOT}/etc/resolv.conf
else
    echo -n "nameserver 8.8.8.8\nnameserver 8.8.4.4\n" > ${ROOT}/etc/resolv.conf
fi

# Append to /etc files
[ -f ${SRC}/${ARCH}/fstab.append ] && cat ${SRC}/${ARCH}/fstab.append >> ${ROOT}/etc/fstab

# Append modules for auto-loading
for mod in ${MODULES_APPEND}; do
    echo ${mod} >> ${ROOT}/etc/modules
done

# Set up networking (and symlink allowing /etc/network/interfaces to be writable)
mkdir -p ${ROOT}/data/links_/etc/network
cat << EOF > ${ROOT}/data/links_/etc/network/interfaces
iface eth0 inet dhcp
EOF
cd ${ROOT}/etc/network

# Enable services
for servce in ${SERVICES_ENABLE}; do
    chroot ${ROOT} /sbin/rc-update add ${service}
done

if [ ! -z "${DOCKER_PULL}" ]; then
    # Run dockerd inside the chroot.
    chroot ${ROOT} /usr/bin/dockerd --storage-driver vfs \
        -H unix:///tmp/docker.sock --pidfile=/tmp/docker.pid > /dev/null 2>&1 &

    # Wait for dockerd to start...
    while [ ! -f ${ROOT}/tmp/docker.pid ]; do
        sleep 0.1
    done
    PID=$(cat ${ROOT}/tmp/docker.pid)

    # Pull images and build manifest...
    echo > ${ROOT}/etc/container.manifest
    for image_tag in ${DOCKER_PULL}; do
        docker -H unix://${ROOT}/tmp/docker.sock pull ${image_tag}
        echo ${image_tag} >> ${ROOT}/etc/container.manifest
    done

    docker -H unix://${ROOT}/tmp/docker.sock image ls

    # Kill dockerd and wait for it to exit.
    kill ${PID} > /dev/null 2>&1
    while kill -0 ${PID} > /dev/null 2>&1; do
        sleep 0.1
    done

    # Remove some unnecessary directories
    rm -rf ${ROOT}/var/lib/docker/runtimes ${ROOT}/var/lib/docker/tmp ${ROOT}/run/*
fi

# Clean up mounts
umount ${ROOT}/dev
umount ${ROOT}/proc
umount ${ROOT}/tmp

cd ${ROOT}
tar -C ${ROOT} -czf ${OUT}/rootfs.tar.gz .
ls -lah ${OUT}/rootfs.tar.gz
