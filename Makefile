SHELL := /bin/bash

.PHONY: setup-none setup-rpi setup-qemu build build-rpi build-qemu

setup-none:
	rm -f build/tmp build/conf/local.conf build/conf/bblayers.conf

setup-rpi: setup-none
	mkdir -p build/tmp.rpi
	cd build && \
		ln -sf tmp.rpi tmp
	cd build/conf && \
		ln -sf bblayers.conf.rpi bblayers.conf && \
		ln -sf local.conf.rpi local.conf

setup-qemu: setup-none
	mkdir -p build/tmp.qemux86-64
	cd build && \
		ln -sf tmp.qemux86-64 tmp
	cd build/conf && \
		ln -sf bblayers.conf.qemux86-64 bblayers.conf && \
		ln -sf local.conf.qemux86-64 local.conf

build:
	source poky/oe-init-build-env build && \
		bitbake core-image-minimal

build-rpi: setup-rpi build

build-qemu: setup-qemu build

clean:
	rm -rf build/tmp.rpi/* build/tmp.qemux86-64 build/tmp build/conf/local.conf build/conf/bblayers.conf
