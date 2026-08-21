# Pterohost Rust dedicated server image.
#
# Native Linux RustDedicated (Steam app 258550) - no Wine, unlike sbox. This
# image OWNS everything the old third-party black box (ghcr.io/sturdystubs/aioegg)
# hid: the framework install (Oxide / Carbon / vanilla), the extension downloads
# and the performance tuning all live in start-rust, so bugs are fixable here
# instead of being patched around from the panel DB.
#
# amd64 only - Facepunch ships no arm64 RustDedicated depot.
#
# Everything the image provides (SteamCMD, jemalloc, start-rust) lives OUTSIDE
# /home/container, because Wings bind-mounts the server volume over that path at
# runtime. The game files, framework and Steam client SDK live in the volume and
# persist across restarts.
FROM debian:12-slim

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Rust (SteamCMD, Oxide/Carbon, jemalloc)"
LABEL org.opencontainers.image.description="RustDedicated (Steam app 258550) with deterministic Oxide/Carbon/vanilla framework install and jemalloc allocator tuning. amd64 only."

ENV DEBIAN_FRONTEND=noninteractive

# 32-bit runtime is required because SteamCMD itself is a 32-bit binary; the
# RustDedicated server is 64-bit. libjemalloc2 is the allocator we preload at
# launch to cut Rust's memory fragmentation (the structural fix for "lag").
# libgdiplus lets the handful of Oxide image plugins that use System.Drawing run.
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg tar unzip xz-utils jq file \
        locales tzdata tini procps iproute2 lsof \
        lib32gcc-s1 lib32stdc++6 libgcc-s1 libstdc++6 \
        libjemalloc2 libgdiplus libsdl2-2.0-0 \
        libnss-wrapper libnss-wrapper:i386 \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && useradd -m -d /home/container -s /bin/bash container \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

# SteamCMD into /opt. Wings runs the game container as its own uid (e.g. 998),
# not the image's `container` user, and SteamCMD self-updates into its own dir -
# so make the tree world-rwx so any runtime uid can exec and write it. start-rust
# copies it into the (writable) server volume before use, because Wings mounts
# the container root read-only.
RUN mkdir -p /opt/steamcmd \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
       | tar -xz -C /opt/steamcmd \
    && chmod -R 0777 /opt/steamcmd

# websocat: static WebSocket client for the panel-console -> WebRCON bridge.
# RustDedicated ignores stdin (where Wings delivers console commands), so
# start-rust forwards those lines to the server's WebRCON socket through this.
ARG WEBSOCAT_VERSION=1.13.0
RUN curl -fsSL -o /usr/local/bin/websocat \
       "https://github.com/vi/websocat/releases/download/v${WEBSOCAT_VERSION}/websocat.x86_64-unknown-linux-musl" \
    && chmod 0755 /usr/local/bin/websocat \
    && /usr/local/bin/websocat --version

ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 \
    USER=container HOME=/home/container \
    STEAMCMD_DIR=/opt/steamcmd \
    JEMALLOC_LIB=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 \
    XDG_RUNTIME_DIR=/tmp \
    PATH=/usr/local/bin:/opt/steamcmd:/usr/bin:/bin \
    PTEROHOST_JDK_TAG=rust

WORKDIR /home/container
COPY --chmod=755 shared/entrypoint.sh /entrypoint.sh
COPY --chmod=755 shared/sysinfo.sh /sysinfo.sh
COPY --chmod=755 shared/launch.sh /usr/local/lib/pterohost/launch.sh
COPY --chmod=755 shared/identity.sh /usr/local/lib/pterohost/identity.sh
COPY shared/motd.txt /motd.txt
COPY shared/nodes.tsv /etc/pterohost/nodes.tsv
COPY --chmod=755 images/rust/start-rust /usr/local/bin/start-rust
USER container

# tini without -g on purpose. With -g it forwards Wings SIGTERM to the whole
# process group, so the game gets it at the same instant as the bootstrap and
# dies before the trap can save the world. Without it only the bootstrap is
# signalled and the graceful stop below stays in control.
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/bin/bash","/entrypoint.sh"]
