ARCH ?= amd64
DOCKER_ARCH ?= ${ARCH}/
ALPINE_VERSION ?= 3.18
KERNEL_IMAGE ?= linux-virt
BUILDER_NAME = homeland-os-builder

.PHONY: build builder out/disk.img

clean-image:
	docker image rm --force ${BUILDER_NAME}

builder: clean-image
	docker build --build-arg ARCH=${ARCH} \
		--build-arg DOCKER_ARCH=${DOCKER_ARCH} \
		--build-arg ALPINE_VERSION=${ALPINE_VERSION} \
		-t ${BUILDER_NAME} .

out/rootfs.tar.gz:
	sudo docker run --runtime=sysbox-runc -ti \
		-e KERNEL_IMAGE=${KERNEL_IMAGE} \
		-v ${PWD}/src:/var/lib/homeland/src \
		-v ${PWD}/out:/var/lib/homeland/out ${BUILDER_NAME} /var/lib/homeland/src/mkrootfs.sh

out/disk.img:
	sudo docker run --privileged --cap-add=CAP_MKNOD -ti \
		-e KERNEL_IMAGE=${KERNEL_IMAGE} \
		-v ${PWD}/src:/var/lib/homeland/src \
		-v ${PWD}/out:/var/lib/homeland/out ${BUILDER_NAME} /var/lib/homeland/src/mkimage.sh

out/disk.vdi:
	qemu-img convert -f raw -O vdi out/disk.img out/disk.vdi

out/disk.qcow2:
	qemu-img convert -f raw -O qcow2 out/disk.img out/disk.qcow2

clean:
	rm -rf out/*
