SHELL = /bin/bash
CONFIG ?= config

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
		-e SRC=/var/lib/homeland/src \
		-e OUT=/var/lib/homeland/out \
		-v ${PWD}/out:/var/lib/homeland/out \
		-v ${PWD}/src:/var/lib/homeland/src:ro \
		-v ${PWD}/entrypoint.sh:/entrypoint.sh:ro ${BUILDER_NAME} /var/lib/homeland/src/mkrootfs.sh

out/disk.img:
	sudo docker run --privileged --cap-add=CAP_MKNOD -ti \
		-e CONFIG=${CONFIG} \
		-e SRC=/var/lib/homeland/src \
		-e OUT=/var/lib/homeland/out \
		-v ${PWD}/out:/var/lib/homeland/out \
		-v ${PWD}/src:/var/lib/homeland/src:ro \
		-v ${PWD}/entrypoint.sh:/entrypoint.sh:ro ${BUILDER_NAME} /var/lib/homeland/src/mkimage.sh

out/disk.vdi:
	qemu-img convert -f raw -O vdi out/disk.img out/disk.vdi

out/disk.qcow2:
	qemu-img convert -f raw -O qcow2 out/disk.img out/disk.qcow2

clean:
	rm -rf out/*
