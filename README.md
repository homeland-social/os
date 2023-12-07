# os
OS build tooling using yocto.

## usage

Building arm64 / rpi image.

```bash
$ docker run --rm --privileged docker/binfmt:66f9012c56a8316f9244ffd7622d7c21c1f6f28d

$ docker buildx create --use --name multi-arch-builder

$ CONFIG=config.rpi make builder
```