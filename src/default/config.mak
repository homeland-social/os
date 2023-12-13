# The values below are common to all other configs although they might be
# overidden by any individual config in src/${ARCH}/config

export ARCH=amd64
export ALPINE_VERSION=3.18
export ALPINE_MIRROR=http://dl-cdn.alpinelinux.org/alpine/

# Sizes in Megabytes, leave DATA_SIZE blank to grow
export DISK_SIZE=3072
export BOOT_SIZE=64
export ROOT_SIZE=384
export DATA_SIZE=

export BOARD_NAME=virt
export NET_ETH=e1000
export PACKAGES_INSTALL=
export SERVICES_ENABLE=
export MODULES_LOAD=

# Important files which are copied to the root fs.
export CONTAINERS_INITD_PATH=default/containers.initd.sh
export CONTAINERS_COMPOSE_PATH=default/containers-compose.yml
export DOCKER_CONFD_PATH=default/docker.confd
export EXPAND_DATA_CONFD_PATH=default/expand-data.confd
export EXPAND_DATA_INITD_PATH=default/expand-data.initd.sh
export FSTAB_APPEND_PATH=default/fstab.append
export RESOLV_CONF_PATH=
# You can run any command at various stages of the build for debugging
# purposes. i.e. setting any of the following to /bin/bash will open a
# manhole.

# mkrootfs.sh hooks:
export HOOK_RUN_AFTER_APK=
export HOOK_RUN_AFTER_FILES=

# mkimage.sh hooks:
export HOOK_RUN_AFTER_LOSETUP=
export HOOK_RUN_BEFORE_UMOUNT=
export HOOK_RUN_BEFORE_TAR=
