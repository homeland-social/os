#!/bin/bash

if [ "${BUILD_ARCH}" != "${ARCH}" ]; then
    echo "ARCH does not equal BUILD_ARCH, rebuild builder container!"
    exit 1
fi

/bin/bash $@
