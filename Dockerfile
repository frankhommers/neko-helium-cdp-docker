# Stage 1: Build Vue client
FROM node:20-alpine AS client-build
COPY client/ /build/
WORKDIR /build
RUN npm ci && npm run build

# Stage 2: Build the damagegate GStreamer plugin (drops unchanged X11 frames)
FROM debian:trixie-slim AS damagegate-build
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends gcc libc6-dev pkg-config \
      libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libx11-dev libxdamage-dev libxfixes-dev && \
    rm -rf /var/lib/apt/lists/*
COPY gst-damagegate/ /src/
RUN gcc -O2 -Wall -Werror -fPIC -shared -o /libgstdamagegate.so /src/gstdamagegate.c \
      $(pkg-config --cflags --libs gstreamer-1.0 gstreamer-base-1.0 gstreamer-video-1.0 x11 xdamage xfixes)

# Stage 3: Final image (Neko base + Helium instead of Google Chrome)
FROM ghcr.io/m1k1o/neko/base:3

# Helium release to install. "latest" resolves the newest GitHub release at build
# time, so the weekly CI rebuild picks up new Helium versions automatically.
ARG HELIUM_VERSION=latest

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends openbox socat iproute2 jq ca-certificates libnss3-tools; \
    if [ "${HELIUM_VERSION}" = "latest" ]; then \
      HELIUM_VERSION="$(wget -qO- https://api.github.com/repos/imputnet/helium-linux/releases/latest | jq -r .tag_name)"; \
    fi; \
    echo "Installing Helium ${HELIUM_VERSION}"; \
    wget -qO /tmp/helium.deb \
      "https://github.com/imputnet/helium-linux/releases/download/${HELIUM_VERSION}/helium-bin_${HELIUM_VERSION}-1_amd64.deb"; \
    apt-get install -y --no-install-recommends /tmp/helium.deb; \
    rm -f /tmp/helium.deb; \
    /opt/helium/helium --version; \
    echo "${HELIUM_VERSION}" > /etc/helium-version; \
    apt-get clean -y; rm -rf /var/lib/apt/lists/* /var/cache/apt/*

COPY --from=damagegate-build /libgstdamagegate.so /usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgstdamagegate.so
RUN rm -rf /var/www/*
COPY --from=client-build /build/dist/ /var/www/

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
# Disable audio: kill PulseAudio config so nothing tries to connect
RUN echo "autospawn = no" > /etc/pulse/client.conf && \
    echo "daemon-binary = /bin/true" >> /etc/pulse/client.conf

# Helium reads managed policies from the Chromium location
COPY policies.json /etc/chromium/policies/managed/policies.json
COPY openbox.xml /etc/neko/openbox.xml
COPY helium.conf /etc/neko/supervisord/helium.conf
COPY cdp-proxy.conf /etc/neko/supervisord/cdp-proxy.conf
