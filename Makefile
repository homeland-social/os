SHELL:=/bin/bash
CONFIG?=config.amd64
VM_NAME?=homeland-test
OWNER?=$(shell id -u)

VERSION?=$(shell git tag | tail -n 1)
BUILDER_NAME=homeland-os-builder

include src/${CONFIG}

.PHONY: build builder out/disk.img

all: disk.img.gz

builder: clean-image
	docker build --build-arg ARCH=${ARCH} \
		--build-arg ARCH=${ARCH} \
		--build-arg DOCKER_ARCH=${ARCH}/ \
		--build-arg ALPINE_VERSION=${ALPINE_VERSION} \
		--build-arg ALPINE_MIRROR=${ALPINE_MIRROR} \
		-t ${BUILDER_NAME} .

out/rootfs-${VERSION}.tar.gz:
	sudo docker run --runtime=sysbox-runc \
		-e ARCH=${ARCH} \
		-e CONFIG=${CONFIG} \
		-e VERSION=${VERSION} \
		-e OWNER=${OWNER} \
		-e SRC=/var/lib/homeland/src \
		-e OUT=/var/lib/homeland/out \
		-v ${PWD}/out:/var/lib/homeland/out \
		-v ${PWD}/src:/var/lib/homeland/src:ro \
		-v ${PWD}/entrypoint.sh:/entrypoint.sh:ro ${BUILDER_NAME} /var/lib/homeland/src/mkrootfs.sh rootfs-${VERSION}.tar.gz

rootfs: out/rootfs-${VERSION}.tar.gz

out/disk-${VERSION}.img: out/rootfs-${VERSION}.tar.gz
	sudo docker run --privileged --cap-add=CAP_MKNOD \
		-e ARCH=${ARCH} \
		-e CONFIG=${CONFIG} \
		-e VERSION=${VERSION} \
		-e OWNER=${OWNER} \
		-e SRC=/var/lib/homeland/src \
		-e OUT=/var/lib/homeland/out \
		-v ${PWD}/out:/var/lib/homeland/out \
		-v ${PWD}/src:/var/lib/homeland/src:ro \
		-v ${PWD}/entrypoint.sh:/entrypoint.sh:ro ${BUILDER_NAME} /var/lib/homeland/src/mkimage.sh rootfs-${VERSION}.tar.gz disk-${VERSION}.img

disk.img: out/disk-${VERSION}.img

disk.img.gz: disk.img
	sha256sum out/disk-${VERSION}.img > out/disk-${VERSION}.img.sha256sum
	sha256sum out/part-${VERSION}.img > out/part-${VERSION}.img.sha256sum
	cat out/disk-${VERSION}.img | gzip -9 > out/disk-${VERSION}.img.gz
	cat out/part-${VERSION}.img | gzip -9 > out/part-${VERSION}.img.gz

out/disk-${VERSION}.vdi:
	qemu-img convert -f raw -O vdi out/disk-${VERSION}.img out/disk-${VERSION}.vdi

out/disk-${VERSION}.qcow2:
	qemu-img convert -f raw -O qcow2 out/disk-${VERSION}.img out/disk-${VERSION}.qcow2

# https://www.virtualbox.org/manual/ch08.html
detachVmDisk:
	-VBoxManage controlvm ${VM_NAME} poweroff
	VBoxManage storageattach ${VM_NAME} --storagectl "SATA" --port 0 --medium none
	VBoxManage closemedium ${PWD}/out/disk.vdi --delete

attachVmDisk: out/disk-${VERSION}.vdi
	VBoxManage storageattach ${VM_NAME} --storagectl "SATA" --port 0 --type hdd --medium ${PWD}/out/disk.vdi
	VBoxManage startvm ${VM_NAME}

clean:
	rm -rf out/*

clean-image:
	docker image rm --force ${BUILDER_NAME}
