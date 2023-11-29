ARG DOCKER_ARCH
ARG ALPINE_VERSION

FROM ${DOCKER_ARCH}alpine:${ALPINE_VERSION}

ARG ARCH
ARG ALPINE_VERSION

ENV ARCH=${ARCH}
ENV ALPINE_VERSION=${ALPINE_VERSION}
ENV ALPINE_MIRROR=http://dl-cdn.alpinelinux.org/alpine/
ENV OUT=/var/lib/homeland/out
ENV SRC=/var/lib/homeland/src
ENV ROOT=/var/lib/homeland/root
ENV PACKAGES="alpine-base docker-engine"

RUN apk update
RUN apk upgrade
RUN apk add alpine-sdk xorriso sfdisk u-boot-tools mkinitfs docker-cli \
        bash tar coreutils e2fsprogs dosfstools partx multipath-tools \
        grub grub-bios

ENTRYPOINT ["/bin/bash"]
