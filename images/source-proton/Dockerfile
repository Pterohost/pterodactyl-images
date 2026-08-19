# Pterohost Source dedicated-server image - the Windows build under GE-Proton.
#
# The optional sibling of the `source` tag. Same games, same start-source
# bootstrap; the only difference is that Steam hands us the WINDOWS depot and
# srcds runs as a PE under Proton.
#
# WHY THIS EXISTS:
#
#   Valve's appinfo for Left 4 Dead 2 Dedicated Server (app 222860) carries one
#   launch entry, srcds.exe, with oslist "windows", and no common.oslist at all.
#   SteamCMD reads that and refuses the app on Linux before it downloads a
#   single byte:
#
#       ERROR! Failed to install app '222860' (Invalid platform)
#
#   Measured 2026-08-19, and it is the app that is refused, not the account:
#   anonymous, a logged-in account, +@sSteamCmdForcePlatformType linux and
#   -beta public all produce the same line. The Linux binaries do exist - depot
#   222863, 243 MB - but anonymous has no license for it and download_depot
#   fails with "missing license for depot". Open upstream since November 2024
#   (ValveSoftware/steam-for-linux#11522, GameServerManagers/LinuxGSM#4754) with
#   no client-side workaround.
#
#   Forcing the platform to windows, on the other hand, downloads normally. So
#   the Windows dedicated server under Proton is the only way to sell this game
#   at all, and that is the entire reason for this image.
#
#   It is NOT faster, and no game whose Linux depot installs should be moved
#   here. Every other appid we ship was checked against the same gate on
#   2026-08-19 and 222860 is the only one that hits it.
#
# WHY NOT `FROM steamcmd_base` LIKE THE NATIVE `source` IMAGE:
#
#   GE-Proton11's ntdll.so is linked against GLIBC_2.38 and the shared base is
#   debian:12-slim, which is 2.36. Ubuntu 24.04 is 2.39. The cost is that the
#   SteamCMD/locale/tini layer is duplicated from images/steamcmd-base rather
#   than inherited - the same trade images/palworld-proton and images/sbox make,
#   and for the same reason. Keep the three in step when the base changes.
#
# srcds.exe is a 32-bit PE, so the i386 runtime here is not only for SteamCMD:
# wine needs the 32-bit build of everything Proton expects from the host.
#
# amd64 only.
FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Source (srcds, Windows depot, GE-Proton)"
LABEL org.opencontainers.image.description="Source dedicated server running the Windows depot under GE-Proton, for Left 4 Dead 2 (app 222860), whose Linux depot Steam refuses to install. amd64 only."

ENV DEBIAN_FRONTEND=noninteractive

# Three groups, exactly as in images/palworld-proton:
#   1. what steamcmd_base carries, because start-source and the shared
#      entrypoint expect it (i386 for SteamCMD, libnss-wrapper both ways because
#      the entrypoint preloads it by soname);
#   2. python3, because Proton's launcher is a Python script;
#   3. the system libraries Proton expects the host to provide - it bundles the
#      rest under files/lib*. libvulkan1 is not optional even headless: the
#      launcher dlopens libvulkan.so.1 before it looks at what it was asked to
#      run, so without it every start dies on a Python traceback.
#
# The :i386 half of group 3 is what a 32-bit srcds.exe needs and a 64-bit
# Palworld does not.
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg tar unzip xz-utils jq file bc \
        locales tzdata tini procps iproute2 lsof net-tools netcat-openbsd \
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
        libasound2t64 \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && useradd -m -d /home/container -s /bin/bash container \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

# The base image ships /etc/machine-id empty and wine reads it on every start.
# The container runs as an arbitrary uid and cannot write the file itself.
RUN head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > /etc/machine-id \
    && chmod 0444 /etc/machine-id

# gorcon: srcds.exe under wine does not read the panel console the way the Linux
# binary does, so RCON is how a graceful "quit" reaches the server on stop.
ARG GORCON_VERSION=0.10.3
RUN curl -fsSL -o /tmp/rcon.tar.gz \
       "https://github.com/gorcon/rcon-cli/releases/download/v${GORCON_VERSION}/rcon-${GORCON_VERSION}-amd64_linux.tar.gz" \
    && tar -xzf /tmp/rcon.tar.gz -C /tmp \
    && install -m 0755 "/tmp/rcon-${GORCON_VERSION}-amd64_linux/rcon" /usr/local/bin/rcon \
    && rm -rf /tmp/rcon.tar.gz "/tmp/rcon-${GORCON_VERSION}-amd64_linux" \
    && /usr/local/bin/rcon --version

# Wings runs the container as the node's own uid and SteamCMD self-updates into
# its own directory, so the tree must be world-rwx for any runtime uid.
RUN mkdir -p /opt/steamcmd \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
       | tar -xz -C /opt/steamcmd \
    && chmod -R 0777 /opt/steamcmd

# GE-Proton rather than Valve's build: it publishes a self-contained tarball on
# a pinnable tag, whereas Valve's ships as a Steam depot whose version cannot be
# fixed for a reproducible build. Same version and checksum as
# images/palworld-proton - bump both together.
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

# srcds.exe is a GUI PE and the Source dedicated server takes the windowed path
# even with -console: the DLLs it loads on the way up are comctl32, dinput8,
# XInput1_4, winex11.drv and the shader modules. With no display it stops there,
# before it ever binds the game port. Xvfb is 4 MB and gives it a screen nobody
# looks at. Separate layer on purpose - added after the Proton tarball so a
# change here does not invalidate a 532 MB download.
RUN apt-get update \
    && apt-get install -y --no-install-recommends xvfb xauth \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

# A wrapper rather than a symlink: the launcher resolves its own toolchain from
# the script's location, and a symlink on PATH would send it looking in
# /usr/local/bin.
RUN printf '#!/bin/sh\nexec python3 /opt/pterohost-proton/proton "$@"\n' > /usr/local/bin/proton \
    && chmod 0755 /usr/local/bin/proton

ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 \
    USER=container HOME=/home/container \
    STEAMCMD_DIR=/opt/steamcmd \
    XDG_RUNTIME_DIR=/tmp \
    PATH=/usr/local/bin:/opt/steamcmd:/usr/bin:/bin \
    PTEROHOST_IMAGE=source_proton \
    PTEROHOST_RUNTIME="Source - srcds (Windows depot, GE-Proton)" \
    PTEROHOST_STEAM_APP="222860" \
    PTEROHOST_NOTES="for Left 4 Dead 2, whose Linux depot Steam refuses to install" \
    SRCDS_RUNTIME=proton \
    PROTON_DIR=/opt/pterohost-proton \
    WINEDEBUG=-all

WORKDIR /home/container
COPY --chmod=755 shared/entrypoint.sh /entrypoint.sh
COPY --chmod=755 shared/sysinfo.sh /sysinfo.sh
COPY --chmod=755 shared/steam-update.sh /usr/local/lib/pterohost/steam-update.sh
COPY --chmod=755 shared/launch.sh /usr/local/lib/pterohost/launch.sh
COPY --chmod=755 shared/kvconf.sh /usr/local/lib/pterohost/kvconf.sh
COPY --chmod=755 shared/cfgconf.sh /usr/local/lib/pterohost/cfgconf.sh
COPY --chmod=755 shared/cvarconf.sh /usr/local/lib/pterohost/cvarconf.sh
COPY shared/motd.txt /motd.txt
COPY shared/nodes.tsv /etc/pterohost/nodes.tsv
COPY --chmod=755 images/source/start-source /usr/local/bin/start-source
USER container

# tini without -g: with it Wings' SIGTERM reaches srcds at the same instant as
# the bootstrap, and the stop path never gets to send "quit" through RCON or to
# shut wineserver down cleanly.
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/bin/bash","/entrypoint.sh"]
