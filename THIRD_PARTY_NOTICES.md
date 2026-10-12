# Third-party notices

This repository includes and modifies components from the upstream Neko project.

## Neko client

- Project: Neko
- Upstream: https://github.com/m1k1o/neko
- Package metadata: `client/package.json`
- Original author listed by upstream package metadata: Nurdism <https://github.com/nurdism>
- License: Apache License 2.0
- Local license copy: `LICENSES/Apache-2.0.txt`

The `client/` directory contains a stripped-down Vue frontend based on Neko's original client. Local changes remove UI features that are not needed for this image, such as chat, emotes, file transfer, members list, sidebar, and about dialog.

## Base image

This Docker image is built from:

```text
ghcr.io/m1k1o/neko/base:3
```

See the upstream Neko project for its own licensing and notices.

## Helium

- Project: Helium (imput)
- Upstream: https://github.com/imputnet/helium-linux, https://github.com/imputnet/helium-chromium
- License: GPL-3.0 (Helium), Chromium components under their own licenses
- Installed unmodified from the official `helium-bin` .deb release at image build time; not redistributed in this repository.

## uBlock Origin

- Project: uBlock Origin (Raymond Hill), shipped by Helium as a built-in component (fork: https://github.com/imputnet/uBlock)
- License: GPL-3.0
- Part of the Helium package; not modified or redistributed by this repository.
