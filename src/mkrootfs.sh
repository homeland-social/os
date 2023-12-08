#!/bin/bash -x

OUTPUT=$1

MODULES_LOAD="${MODULES_LOAD} ${NET_ETH}"
PACKAGES_INSTALL="${PACKAGES_INSTALL} docker-engine alpine-base grub linux-${BOARD_NAME} cloud-utils-growpart e2fsprogs e2fsprogs-extra"
SERVICES_ENABLE="${SERVICES_ENABLE} networking modules docker expand-data sysctl"

if [ "${NET_WIFI}" == "yes" ]; then
    PACKAGES_INSTALL="${PACKAGES_INSTALL} wpa_supplicant wireless-tools hostapd dnsmasq dnsmasq-openrc"
    SERVICES_ENABLE="${SERVICES_ENABLE} wpa_supplicant hostapd dnsmasq"
fi

ROOT=/tmp/root
mkdir -p ${ROOT}
mkdir -p ${ROOT}/etc/apk
cp -R /etc/apk ${ROOT}/etc/

apk add -U \
    -X "${ALPINE_MIRROR}v${ALPINE_VERSION}/main" \
    -X "${ALPINE_MIRROR}v${ALPINE_VERSION}/community" \
    --no-cache --allow-untrusted --initdb -p ${ROOT} ${PACKAGES_INSTALL}

[ ! -z "${HOOK_RUN_AFTER_APK}" ] && ${HOOK_RUN_AFTER_APK}

mkdir -p ${ROOT}/var/lib/homeland/

mount -o bind /dev ${ROOT}/dev
mount -o bind /proc ${ROOT}/proc
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
    mkdir -p ${ROOT}/data/link_/etc/network
    echo homeland > ${ROOT}/etc/hostname
    cat > ${ROOT}/data/link_/etc/network/interfaces <<EOF
auto lo
auto eth0
iface lo inet loopback
iface eth0 inet dhcp
EOF
    cd ${ROOT}/etc/network && ln -sf /data/link_/etc/network/interfaces interfaces
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
    chroot ${ROOT} /usr/bin/dockerd --storage-driver=vfs \
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

# Clean up mounts
umount ${ROOT}/dev
umount ${ROOT}/proc
umount ${ROOT}/tmp

cd ${ROOT} || exit 1
tar -C ${ROOT} -czf "${OUT}/${OUTPUT}" .
ls -lah "${OUT}/${OUTPUT}"
