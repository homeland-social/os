#!/bin/bash -x

mkdir -p ${ROOT}

apk add -U -X ${ALPINE_MIRROR}v${ALPINE_VERSION}/main \
    -X ${ALPINE_MIRROR}v${ALPINE_VERSION}/community \
    --no-cache --allow-untrusted --initdb -p ${ROOT} ${PACKAGES} ${KERNEL_IMAGE} grub
apk del --no-cache -p --force-broken-world ${ROOT} apk-tools

mkdir -p ${ROOT}/var/lib/homeland/
cp ${SRC}/${ARCH}/container.manifest ${ROOT}/var/lib/homeland/

mount -o bind /dev ${ROOT}/dev
mount -o bind /proc ${ROOT}/proc
mount -o bind /tmp ${ROOT}/tmp

# Create r/w mount point
mkdir -p ${ROOT}/data

# This will be useful
cat << EOF > ${ROOT}/etc/resolv.conf
# Generated at build time
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

[ -f ${SRC}/fstab.append ] && cat ${SRC}/fstab.append >> ${ROOT}/etc/fstab

# Run dockerd inside the chroot.
chroot ${ROOT} /usr/bin/dockerd --storage-driver vfs \
    -H unix:///tmp/docker.sock --pidfile=/tmp/docker.pid 2>&1 > /dev/null &

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

# Remove some unnecessary directories
rm -rf ${ROOT}/var/lib/docker/runtimes ${ROOT}/var/lib/docker/tmp ${ROOT}/run/*

# Kill dockerd and wait for it to exit.
kill ${PID}
while kill -0 ${PID} 2>&1 > /dev/null; do
    sleep 0.1
done

# Clean up mounts
umount ${ROOT}/dev
umount ${ROOT}/proc
umount ${ROOT}/tmp

tar -C ${ROOT}/boot -czf ${OUT}/bootfs.tar.gz . && rm -rf ${ROOT}/boot/*
tar -C ${ROOT} -czf ${OUT}/rootfs.tar.gz .
