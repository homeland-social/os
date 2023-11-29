ARG DOCKER_ARCH
ARG ALPINE_VERSION

FROM ${DOCKER_ARCH}alpine:${ALPINE_VERSION}

ARG ARCH
ARG ALPINE_VERSION
ARG ALPINE_MIRROR

ENV BUILD_ARCH=${ARCH}
ENV ALPINE_VERSION=${ALPINE_VERSION}
ENV ALPINE_MIRROR=http://dl-cdn.alpinelinux.org/alpine/

RUN apk update
RUN apk upgrade
RUN apk add alpine-sdk xorriso sfdisk u-boot-tools mkinitfs docker-cli \
        bash tar coreutils e2fsprogs dosfstools partx multipath-tools \
        grub grub-bios

ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
