SHELL:=/bin/bash
CONFIG?=config.amd64
VM_NAME?=homeland-test
OWNER?=$(shell id -u)

VERSION?=$(shell git tag | tail -n 1)

include src/${CONFIG}

.PHONY: build builder out/disk.img

all: disk.img.gz

out:
	mkdir out

out/rootfs-${BOARD_NAME}-${ARCH}-${VERSION}.tar.gz: out
	sudo docker run -ti --runtime=sysbox-runc --platform=${ARCH} \
		-e ARCH=${ARCH} \
		-e CONFIG=${CONFIG} \
		-e VERSION=${VERSION} \
		-e SRC=/var/lib/homeland/src \
		-e OUT=/var/lib/homeland/out \
		-v ${PWD}/out:/var/lib/homeland/out \
		-v ${PWD}/src:/var/lib/homeland/src:ro \
		-v ${PWD}/entrypoint.sh:/entrypoint.sh:ro alpine:${ALPINE_VERSION} \
		/var/lib/homeland/src/setup.sh \
		/var/lib/homeland/src/mkrootfs.sh rootfs-${BOARD_NAME}-${ARCH}-${VERSION}.tar.gz
	sudo chown ${OWNER}:${OWNER} out/rootfs-${BOARD_NAME}-${ARCH}-${VERSION}.tar.gz

rootfs.tar.gz: out/rootfs-${BOARD_NAME}-${ARCH}-${VERSION}.tar.gz

out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img: out/rootfs-${BOARD_NAME}-${ARCH}-${VERSION}.tar.gz
	sudo docker run -ti --privileged --cap-add=CAP_MKNOD --platform=${ARCH} \
		-e ARCH=${ARCH} \
		-e CONFIG=${CONFIG} \
		-e VERSION=${VERSION} \
		-e SRC=/var/lib/homeland/src \
		-e OUT=/var/lib/homeland/out \
		-v ${PWD}/out:/var/lib/homeland/out \
		-v ${PWD}/src:/var/lib/homeland/src:ro \
		-v ${PWD}/entrypoint.sh:/entrypoint.sh:ro alpine:${ALPINE_VERSION} \
		/var/lib/homeland/src/setup.sh \
		/var/lib/homeland/src/mkimage.sh rootfs-${BOARD_NAME}-${ARCH}-${VERSION}.tar.gz disk-${BOARD_NAME}-${ARCH}-${VERSION}.img
	sudo chown ${OWNER}:${OWNER} out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img

disk.img: out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img

disk.img.gz: disk.img
	sha256sum out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img > out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img.sha256sum
	sha256sum out/part-${BOARD_NAME}-${ARCH}-${VERSION}.img > out/part-${BOARD_NAME}-${ARCH}-${VERSION}.img.sha256sum
	cat out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img | gzip -9 > out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img.gz
	cat out/part-${BOARD_NAME}-${ARCH}-${VERSION}.img | gzip -9 > out/part-${BOARD_NAME}-${ARCH}-${VERSION}.img.gz

out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.vdi:
	qemu-img convert -f raw -O vdi out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.vdi

out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.qcow2:
	qemu-img convert -f raw -O qcow2 out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.qcow2

disk.qcow2: out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.qcow2

qemu-down:

qemu-up:
	qemu-system-x86_64 -enable-kvm -drive format=qcow2,file=out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.qcow2 \
		-m 1024M \
		-device usb-ehci,id=ehci \
		-device usb-host,id=ralink,bus=ehci.0,vendorid=0x148f,productid=0x5370

# https://www.virtualbox.org/manual/ch08.html
vbox-create:
	VBoxManage createvm ${VM_NAME}

vbox-down:
	-VBoxManage controlvm ${VM_NAME} poweroff
	-VBoxManage storageattach ${VM_NAME} --storagectl "SATA" --port 0 --medium none
	VBoxManage closemedium ${PWD}/out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.vdi --delete

vbox-up: out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.vdi
	VBoxManage storageattach ${VM_NAME} --storagectl "SATA" --port 0 --type hdd --medium ${PWD}/out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.vdi
	VBoxManage startvm ${VM_NAME}

vbox-remove:
	VBoxManage unregistervm ${VM_NAME}

clean:
	rm -rf out/*

clean-image:
	docker image rm --force ${BUILDER_NAME}
