SHELL:=/bin/bash
CONFIG?=config.amd64
VM_NAME?=homeland-test
OWNER?=$(shell id -u)

VERSION?=$(shell git tag | tail -n 1)
#BUILDER_NAME=homeland-os-builder

include src/${CONFIG}

.PHONY: build builder out/disk.img

all: disk.img.gz

out:
	mkdir out

#builder: clean-image
#	docker buildx build --builder=multi-arch-builder --load --platform=arm64/v8 --build-arg ARCH=${ARCH} \
#		--build-arg ARCH=${ARCH} \
#		--build-arg DOCKER_ARCH=${ARCH}/ \
#		--build-arg ALPINE_VERSION=${ALPINE_VERSION} \
#		--build-arg ALPINE_MIRROR=${ALPINE_MIRROR} \
#		-t ${BUILDER_NAME} .

out/rootfs-${ARCH}-${VERSION}.tar.gz: out
	sudo docker run --runtime=sysbox-runc --platform=${ARCH} \
		-e ARCH=${ARCH} \
		-e CONFIG=${CONFIG} \
		-e VERSION=${VERSION} \
		-e SRC=/var/lib/homeland/src \
		-e OUT=/var/lib/homeland/out \
		-v ${PWD}/out:/var/lib/homeland/out \
		-v ${PWD}/src:/var/lib/homeland/src:ro \
		-v ${PWD}/entrypoint.sh:/entrypoint.sh:ro alpine:${ALPINE_VERSION} \
		/var/lib/homeland/src/setup.sh \
		/var/lib/homeland/src/mkrootfs.sh rootfs-${ARCH}-${VERSION}.tar.gz
	sudo chown ${OWNER}:${OWNER} out/rootfs-${ARCH}-${VERSION}.tar.gz

rootfs.tar.gz: out/rootfs-${ARCH}-${VERSION}.tar.gz

out/disk-${ARCH}-${VERSION}.img: out/rootfs-${ARCH}-${VERSION}.tar.gz
	sudo docker run --privileged --cap-add=CAP_MKNOD --platform=${ARCH} \
		-e ARCH=${ARCH} \
		-e CONFIG=${CONFIG} \
		-e VERSION=${VERSION} \
		-e SRC=/var/lib/homeland/src \
		-e OUT=/var/lib/homeland/out \
		-v ${PWD}/out:/var/lib/homeland/out \
		-v ${PWD}/src:/var/lib/homeland/src:ro \
		-v ${PWD}/entrypoint.sh:/entrypoint.sh:ro alpine:${ALPINE_VERSION} \
		/var/lib/homeland/src/setup.sh \
		/var/lib/homeland/src/mkimage.sh rootfs-${ARCH}-${VERSION}.tar.gz disk-${ARCH}-${VERSION}.img
	sudo chown ${OWNER}:${OWNER} out/disk-${ARCH}-${VERSION}.img

disk.img: out/disk-${ARCH}-${VERSION}.img

disk.img.gz: disk.img
	sha256sum out/disk-${ARCH}-${VERSION}.img > out/disk-${ARCH}-${VERSION}.img.sha256sum
	sha256sum out/part-${ARCH}-${VERSION}.img > out/part-${ARCH}-${VERSION}.img.sha256sum
	cat out/disk-${ARCH}-${VERSION}.img | gzip -9 > out/disk-${ARCH}-${VERSION}.img.gz
	cat out/part-${ARCH}-${VERSION}.img | gzip -9 > out/part-${ARCH}-${VERSION}.img.gz

out/disk-${ARCH}-${VERSION}.vdi:
	qemu-img convert -f raw -O vdi out/disk-${ARCH}-${VERSION}.img out/disk-${ARCH}-${VERSION}.vdi

out/disk-${ARCH}-${VERSION}.qcow2:
	qemu-img convert -f raw -O qcow2 out/disk-${ARCH}-${VERSION}.img out/disk-${ARCH}-${VERSION}.qcow2

# https://www.virtualbox.org/manual/ch08.html
vbox-create:
	VBoxManage createvm ${VM_NAME}

vbox-down:
	-VBoxManage controlvm ${VM_NAME} poweroff
	-VBoxManage storageattach ${VM_NAME} --storagectl "SATA" --port 0 --medium none
	VBoxManage closemedium ${PWD}/out/disk-${ARCH}-${VERSION}.vdi --delete

vbox-up: out/disk-${ARCH}-${VERSION}.vdi
	VBoxManage storageattach ${VM_NAME} --storagectl "SATA" --port 0 --type hdd --medium ${PWD}/out/disk-${ARCH}-${VERSION}.vdi
	VBoxManage startvm ${VM_NAME}

vbox-remove:
	VBoxManage unregistervm ${VM_NAME}

clean:
	rm -rf out/*

clean-image:
	docker image rm --force ${BUILDER_NAME}
