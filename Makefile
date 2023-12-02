SHELL = /bin/bash
CONFIG ?= config.amd64
VM_NAME ?= Test

VERSION = 1.0.1
BUILDER_NAME = homeland-os-builder

.PHONY: build builder out/disk.img

clean-image:
	docker image rm --force ${BUILDER_NAME}

builder: clean-image
	source src/${CONFIG} && \
	docker build --build-arg ARCH=${ARCH} \
		--build-arg DOCKER_ARCH=${ARCH}/ \
		--build-arg ALPINE_VERSION=${ALPINE_VERSION} \
		-t ${BUILDER_NAME} .

out/rootfs.tar.gz:
	sudo docker run --runtime=sysbox-runc -ti \
		-e CONFIG=${CONFIG} \
		-e VERSION=${VERSION} \
		-e SRC=/var/lib/homeland/src \
		-e OUT=/var/lib/homeland/out \
		-v ${PWD}/out:/var/lib/homeland/out \
		-v ${PWD}/src:/var/lib/homeland/src:ro \
		-v ${PWD}/entrypoint.sh:/entrypoint.sh:ro ${BUILDER_NAME} /var/lib/homeland/src/mkrootfs.sh out/rootfs-${VERSIONS}.tar.gz

out/disk.img:
	sudo docker run --privileged --cap-add=CAP_MKNOD -ti \
		-e CONFIG=${CONFIG} \
		-e VERSION=${VERSION} \
		-e SRC=/var/lib/homeland/src \
		-e OUT=/var/lib/homeland/out \
		-v ${PWD}/out:/var/lib/homeland/out \
		-v ${PWD}/src:/var/lib/homeland/src:ro \
		-v ${PWD}/entrypoint.sh:/entrypoint.sh:ro ${BUILDER_NAME} /var/lib/homeland/src/mkimage.sh out/rootfs-${VERSION}.tar.gz out/disk-${VERSION}.img

out/disk.vdi:
	qemu-img convert -f raw -O vdi out/disk.img out/disk.vdi

out/disk.qcow2:
	qemu-img convert -f raw -O qcow2 out/disk.img out/disk.qcow2

# https://www.virtualbox.org/manual/ch08.html
detachVmDisk:
	-VBoxManage controlvm ${VM_NAME} poweroff
	VBoxManage storageattach ${VM_NAME} --storagectl "SATA" --port 0 --medium none
	VBoxManage closemedium ${PWD}/out/disk.vdi --delete

attachVmDisk: out/disk.vdi
	VBoxManage storageattach ${VM_NAME} --storagectl "SATA" --port 0 --type hdd --medium ${PWD}/out/disk.vdi
	VBoxManage startvm ${VM_NAME}

clean:
	rm -rf out/*
