SHELL:=/bin/bash
CONFIG?=amd64
VM_NAME?=homeland-test
OWNER?=$(shell id -u)

VERSION?=$(shell git tag | tail -n 1)

BUILD_ROOT=$(shell pwd)

include ${BUILD_ROOT}/src/${CONFIG}/config.mak

.PHONY: build builder out/disk.img

deps:
	sudo apt install -y qemu-utils

all: disk.img.gz

out:
	mkdir out

out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img:
	sudo docker run --privileged --platform=${ARCH} \
		-e ARCH=${ARCH} \
		-e CONFIG=${CONFIG} \
		-e VERSION=${VERSION} \
		-e SRC=/var/lib/homeland/src \
		-e OUT=/var/lib/homeland/out \
		-e BUILD_ROOT=/var/lib/homeland \
		-v ${PWD}/out:/var/lib/homeland/out \
		-v ${PWD}/src:/var/lib/homeland/src:ro \
		-v ${PWD}/entrypoint.sh:/entrypoint.sh:ro alpine:${ALPINE_VERSION} \
		/var/lib/homeland/src/setup.sh \
		/var/lib/homeland/src/mkimage.sh disk-${BOARD_NAME}-${ARCH}-${VERSION}.img
	sudo chown -R ${OWNER}:${OWNER} out

disk.img: out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img

disk.img.sha256:
	sha256sum out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img > out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img.sha256sum

part.img.sha256:
	sha256sum out/part-${BOARD_NAME}-${ARCH}-${VERSION}.img > out/part-${BOARD_NAME}-${ARCH}-${VERSION}.img.sha256sum

disk.img.gz: disk.img
	cat out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img | gzip -9 > out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.img.gz

part.img.gz:
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
# https://www.paulligocki.com/create-virtualbox-vm-from-command-line/#Configuring-a-Virtual-Network-Adapter
vbox-create:
	VBoxManage createvm --name=${VM_NAME} --register --ostype=linux
	VBoxManage modifyvm ${VM_NAME} --cpus 1 --memory 1024 --vram 16
	VBoxManage modifyvm ${VM_NAME} --nic1 bridged --bridgeadapter1 eth0
	VBoxManage storagectl ${VM_NAME} --name "SATA" --add sata --bootable on

vbox-down:
	-VBoxManage controlvm ${VM_NAME} poweroff
	-VBoxManage storageattach ${VM_NAME} --storagectl "SATA" --port 0 --medium none
	VBoxManage closemedium ${PWD}/out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.vdi --delete

vbox-up: out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.vdi
	VBoxManage storageattach ${VM_NAME} --storagectl "SATA" --port 0 --type hdd --medium ${PWD}/out/disk-${BOARD_NAME}-${ARCH}-${VERSION}.vdi
	VBoxManage startvm ${VM_NAME}

vbox-remove:
	VBoxManage unregistervm --delete ${VM_NAME}

clean:
	rm -rf out/*

clean-image:
	docker image rm --force ${BUILDER_NAME}
