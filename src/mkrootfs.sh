#!/bin/bash -x

OUTPUT=$1

source ${SRC}/${CONFIG}

PACKAGES_INSTALL="${PACKAGES_INSTALL} docker-engine alpine-base grub linux-${BOARD_NAME} cloud-utils-growpart e2fsprogs e2fsprogs-extra"
SERVICES_ENABLE="${SERVICES_ENABLE} networking modules docker containers expand-data"

if [ "NET_WIFI" == "yes" ]; then
    PACKAGES_INSTALL="${PACKAGES_INSTALL} iwd"
    SERVICES_ENABLE="${SERVICES_ENABLE} iwd"
fi

ROOT=/tmp/root
mkdir -p ${ROOT}

apk add -U \
    -X ${ALPINE_MIRROR}v${ALPINE_VERSION}/main \
    -X ${ALPINE_MIRROR}v${ALPINE_VERSION}/community \
    -X ${ALPINE_MIRROR}v${ALPINE_VERSION}/edge \
    --no-cache --allow-untrusted --initdb -p ${ROOT} ${PACKAGES_INSTALL}
apk del --no-cache -p ${ROOT} --force-broken-world apk-tools

[ ! -z "${HOOK_RUN_AFTER_APK}" ] && ${HOOK_RUN_AFTER_APK}

mkdir -p ${ROOT}/var/lib/homeland/

mount -o bind /dev ${ROOT}/dev
mount -o bind /proc ${ROOT}/proc
mount -o bind /tmp ${ROOT}/tmp

# Create r/w mount point
mkdir -p ${ROOT}/data

cp ${SRC}/${ARCH}/docker.confd ${ROOT}/etc/conf.d/docker
cp ${SRC}/${ARCH}/containers.initd ${ROOT}/etc/init.d/containers
cp ${SRC}/${ARCH}/expand-data.confd ${ROOT}/etc/conf.d/expand-data
cp ${SRC}/${ARCH}/expand-data.initd ${ROOT}/etc/init.d/expand-data
chmod +x ${ROOT}/etc/init.d/containers
chmod +x ${ROOT}/etc/init.d/expand-data

# This will be useful
if [ -f ${SRC}/${ARCH}/resolv.conf ]; then
    cp ${SRC}/${ARCH}/resolv.conf ${ROOT}/etc/resolv.conf
else
    echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4\n" > ${ROOT}/etc/resolv.conf
fi

# Append to /etc files
[ -f ${SRC}/${ARCH}/fstab.append ] && cat ${SRC}/${ARCH}/fstab.append >> ${ROOT}/etc/fstab

# Append modules for auto-loading
for mod in ${MODULES_APPEND}; do
    echo ${mod} >> ${ROOT}/etc/modules
done

# Set up networking (and symlink allowing /etc/network/interfaces to be writable)
mkdir -p ${ROOT}/data/links_/etc/network
cat > ${ROOT}/data/links_/etc/network/interfaces <<EOF
iface eth0 inet dhcp
EOF
cd ${ROOT}/etc/network && ln -sf /data/links_/etc/network/interfaces interfaces

# Enable services
for service in ${SERVICES_ENABLE}; do
    chroot ${ROOT} /sbin/rc-update add ${service}
done

# NOTE: this is fixed in alpine 3.19:
# https://github.com/alpinelinux/aports/commit/3a8f76ba962aca7c4553f3dd138ba5b0edabcb2e
chroot ${ROOT} /usr/sbin/addgroup -S docker 2> /dev/null

[ ! -z "${HOOK_RUN_AFTER_FILES}" ] && ${HOOK_RUN_AFTER_FILES}

if [ ! -z "${DOCKER_PULL}" ]; then
    # Run dockerd inside the chroot.
    chroot ${ROOT} /usr/bin/dockerd --storage-driver vfs \
        -H unix:///tmp/docker.sock --pidfile=/tmp/docker.pid > /dev/null 2>&1 &

    # Wait for dockerd to start...
    while [ ! -f ${ROOT}/tmp/docker.pid ]; do
        sleep 0.1
    done
    PID=$(cat ${ROOT}/tmp/docker.pid)

    # Pull images and build default manifest...
    echo > /tmp/containers.manifest
    for image_tag in ${DOCKER_PULL}; do
        docker -H unix://${ROOT}/tmp/docker.sock pull ${image_tag}
        echo ${image_tag} >> /tmp/containers.manifest
    done

    # Use manifest provided in src, otherwise use the default one we generated
    # in the previous step.
    if [ -f ${SRC}/${ARCH}/containers.manifest ]; then
        cp ${SRC}/${ARCH}/containers.manifest ${ROOT}/etc/containers.manifest
    else
        cp /tmp/containers.manifest ${ROOT}/etc/containers.manifest
    fi

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
tar -C ${ROOT} -czf ${OUT}/${OUTPUT} .
ls -lah ${OUT}/${OUTPUT}
