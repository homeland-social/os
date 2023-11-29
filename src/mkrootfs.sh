#!/bin/bash -x

BASE_PACKAGES="grub iwd"

mkdir -p ${ROOT}

apk add -U -X ${ALPINE_MIRROR}v${ALPINE_VERSION}/main \
    -X ${ALPINE_MIRROR}v${ALPINE_VERSION}/community \
    --no-cache --allow-untrusted --initdb -p ${ROOT} ${PACKAGES} ${KERNEL_IMAGE} ${BASE_PACKAGES}
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
cat << EOF > ${ROOT}/etc/resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

# Append to /etc/fstab
[ -f ${SRC}/${ARCH}/fstab.append ] && cat ${SRC}/${ARCH}/fstab.append >> ${ROOT}/etc/fstab

# Set up networking (and symlink allowing /etc/network/interfaces to be writable)
mkdir -p ${ROOT}/data/links_/etc/network
cat << EOF > ${ROOT}/data/links_/etc/network/interfaces
iface eth0 inet dhcp
EOF
cd ${ROOT}/etc/network

# Enable services
chroot ${ROOT} /bin/sh <<"EOF"
ln -sf /data/links_/etc/network/interfaces /etc/network/interfaces

/sbin/rc-update add networking
/sbin/rc-update add iwd
/sbin/rc-update add docker
EOF

# Run dockerd inside the chroot.
chroot ${ROOT} /usr/bin/dockerd --storage-driver vfs \
    -H unix:///tmp/docker.sock --pidfile=/tmp/docker.pid > /dev/null 2>&1 &

# Wait for dockerd to start...
while [ ! -f ${ROOT}/tmp/docker.pid ]; do
    sleep 0.1
done
PID=$(cat ${ROOT}/tmp/docker.pid)

# Pull images from our manifest...
cat ${ROOT}/var/lib/homeland/container.manifest
while read -r name tag; do
    docker -H unix://${ROOT}/tmp/docker.sock pull ${name}:${tag}
done < ${ROOT}/var/lib/homeland/container.manifest

docker -H unix://${ROOT}/tmp/docker.sock image ls

# Kill dockerd and wait for it to exit.
kill ${PID} > /dev/null 2>&1
while kill -0 ${PID} > /dev/null 2>&1; do
    sleep 0.1
done

# Remove some unnecessary directories
rm -rf ${ROOT}/var/lib/docker/runtimes ${ROOT}/var/lib/docker/tmp ${ROOT}/run/*

# Clean up mounts
umount ${ROOT}/dev
umount ${ROOT}/proc
umount ${ROOT}/tmp

cd ${ROOT}
tar -C ${ROOT} -czf ${OUT}/rootfs.tar.gz .
ls -lah ${OUT}/rootfs.tar.gz
