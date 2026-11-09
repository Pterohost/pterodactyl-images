# Pterohost Enshrouded image - the Windows dedicated server under GE-Proton.
#
# Enshrouded ships no Linux server, so a translation layer is unavoidable. The
# community egg ran it on plain wine behind an Xvfb display and stopped it with
# a bare Ctrl+C that killed the container within a second: the world file was
# not written, so every stop lost the progress since the last autosave. Here
# the bootstrap owns the stop and waits for the save (measured: world0.ksd is
# rewritten at the stop, the exit is clean), and no display server runs.
#
# Idle cost, measured on an empty server: ~0.35 of a core on either runtime.
# Most of it is the game's own network loop, which polls for the last
# millisecond of every 5 ms tick; that does not depend on the translation
# layer. GE-Proton switches thread synchronisation to futexes (fsync) wherever
# the container may call futex_waitv, which removes wineserver's share
# (~0.12 core and ~22k context switches a second); elsewhere it falls back to
# wineserver on its own.
#
# Same base as images/palworld-proton and for the same reason: GE-Proton11's
# ntdll.so needs glibc >= 2.38, the shared SteamCMD base is debian:12 (2.36).
#
# Everything the image provides lives outside /home/container, which Wings
# bind-mounts over at runtime. The game files and the wine prefix live in the
# server volume and persist.
#
# amd64 only.
FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Enshrouded (GE-Proton)"
LABEL org.opencontainers.image.description="Enshrouded dedicated server (Steam app 2278520) on GE-Proton, headless, saves on stop. amd64 only."

ENV DEBIAN_FRONTEND=noninteractive

# Base tooling the shared entrypoint and SteamCMD expect (see palworld-proton
# for the reasoning per group), python3 for Proton's launcher, and the few
# system libraries Proton does not bundle. libvulkan1 is required even headless:
# the launcher dlopens it before looking at what it was asked to run.
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget tar unzip xz-utils jq file \
        locales tzdata tini procps iproute2 \
        lib32gcc-s1 lib32stdc++6 libgcc-s1 libstdc++6 lib32z1 zlib1g \
        libnss-wrapper libnss-wrapper:i386 \
        python3 \
        libfreetype6 libfreetype6:i386 \
        libgnutls30t64 libgnutls30t64:i386 \
        libxml2 libxml2:i386 \
        libx11-6 libx11-6:i386 \
        libxext6 libxext6:i386 \
        libgl1 libgl1:i386 \
        libvulkan1 libvulkan1:i386 \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && useradd -m -d /home/container -s /bin/bash container \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

# wine reads /etc/machine-id on every start and complains when it is empty.
RUN head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > /etc/machine-id \
    && chmod 0444 /etc/machine-id

# World-writable: Wings runs the container as the node's own uid, and SteamCMD
# self-updates into its own directory.
RUN mkdir -p /opt/steamcmd \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
       | tar -xz -C /opt/steamcmd \
    && chmod -R 0777 /opt/steamcmd

# Pinned GE-Proton, the same build as palworld-proton.
ARG GE_PROTON_VERSION=GE-Proton11-3
ARG GE_PROTON_SHA512=528ae7831f909c0a4fff5d83889ac6dab3c9706746cd148f05f3064ac042763853d68277e2a815f18f16c17285d5d128864a03c563956c0dce30bafcd16aa77c
RUN mkdir -p /opt/pterohost-proton \
    && curl -fsSL -o /tmp/proton.tar.gz \
       "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${GE_PROTON_VERSION}/${GE_PROTON_VERSION}.tar.gz" \
    && echo "${GE_PROTON_SHA512}  /tmp/proton.tar.gz" | sha512sum -c - \
    && tar -xzf /tmp/proton.tar.gz -C /opt/pterohost-proton --strip-components=1 \
    && rm -f /tmp/proton.tar.gz \
    && test -f /opt/pterohost-proton/proton \
    && chmod -R a+rX /opt/pterohost-proton

# A wrapper, not a symlink: the launcher resolves its toolchain from its own path.
RUN printf '#!/bin/sh\nexec python3 /opt/pterohost-proton/proton "$@"\n' > /usr/local/bin/proton \
    && chmod 0755 /usr/local/bin/proton

ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 \
    USER=container HOME=/home/container \
    STEAMCMD_DIR=/opt/steamcmd \
    XDG_RUNTIME_DIR=/tmp \
    PATH=/usr/local/bin:/opt/steamcmd:/usr/bin:/bin \
    PTEROHOST_IMAGE=enshrouded \
    PTEROHOST_RUNTIME="Enshrouded - Windows server on GE-Proton (headless)" \
    PTEROHOST_STEAM_APP="2278520" \
    SRCDS_APPID=2278520 \
    PROTON_DIR=/opt/pterohost-proton \
    WINEDEBUG=-all

WORKDIR /home/container
COPY --chmod=755 shared/entrypoint.sh /entrypoint.sh
COPY --chmod=755 shared/sysinfo.sh /sysinfo.sh
COPY --chmod=755 shared/steam-update.sh /usr/local/lib/pterohost/steam-update.sh
COPY --chmod=755 shared/launch.sh /usr/local/lib/pterohost/launch.sh
COPY shared/motd.txt /motd.txt
COPY shared/nodes.tsv /etc/pterohost/nodes.tsv
COPY --chmod=755 images/enshrouded/start-enshrouded /usr/local/bin/start-enshrouded

USER container

# tini without -g: only the bootstrap gets Wings' signal, so its stop path
# stays in control of the shutdown instead of the game dying mid-save.
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/bin/bash","/entrypoint.sh"]
