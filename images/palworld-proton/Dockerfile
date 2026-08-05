# Pterohost Palworld image - Windows depot under GE-Proton.
#
# The optional sibling of the `palworld` tag. Same game, same egg, same
# start-palworld bootstrap; the only difference is that Steam hands us the
# WINDOWS depot and the server runs as a PE under Proton.
#
# WHY THIS EXISTS, AND THE ONE THING IT IS NOT FOR:
#
#   Palworld's mod ecosystem is RE-UE4SS, which is a Windows DLL injected into
#   PalServer-Win64-Shipping.exe. There is no Linux equivalent and none is
#   coming, so a server that wants mods has to run the Windows build. That is
#   the entire reason for this image.
#
#   It is NOT faster. Proton is a translation layer on top of a game that is
#   already brutally single-thread bound, and the native depot beats it on every
#   metric that is not "can I load a mod". Anyone switching to this tag for
#   performance is making their server slower. Say so when it comes up.
#
# WHY NOT `FROM steamcmd_base` LIKE EVERY OTHER GAME IMAGE:
#
#   GE-Proton11's ntdll.so is linked against GLIBC_2.38. The shared base is
#   debian:12-slim, which is 2.36, so the prefix builds and then every launch
#   dies on "could not load ntdll.so". Ubuntu 24.04 is 2.39. The cost is that
#   the SteamCMD/gorcon/locale layer below is duplicated from
#   images/steamcmd-base rather than inherited - the same trade images/sbox
#   makes, and for the same reason. Keep the two in step when the base changes.
#
# Everything the image provides lives OUTSIDE /home/container, because Wings
# bind-mounts the server volume over that path at runtime. The wine prefix, the
# game files and the owner's mods live in the volume and persist; start-palworld
# syncs the mod loader in on each boot.
#
# amd64 only - Pocketpair publishes no arm64 depot, and neither does Proton.
FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Palworld (Windows depot, GE-Proton, RE-UE4SS)"
LABEL org.opencontainers.image.description="Palworld dedicated server (Steam app 2394010) running the Windows depot under GE-Proton so RE-UE4SS mods load. Slower than the native `palworld` tag - pick this one only for mod support. amd64 only."

ENV DEBIAN_FRONTEND=noninteractive

# Three groups here:
#
#   1. the same base tooling steamcmd_base carries, because start-palworld and
#      the shared entrypoint expect it (i386 for SteamCMD, which is a 32-bit
#      binary; libnss-wrapper both ways, because the entrypoint preloads it by
#      soname and only the loader knows which build a process needs);
#   2. python3, because Proton's launcher is a Python script;
#   3. the handful of system libraries Proton expects the surrounding runtime to
#      provide - it bundles the rest itself under files/lib*.
#
# Group 3 is deliberately small: a headless dedicated server never opens a
# window, so the X/GL side is only here because wine probes for it while
# building the prefix and is noisy when it is missing. libvulkan1 is the
# exception that is not optional - the launcher imports its vulkan module at the
# top of the file and dlopens libvulkan.so.1 before it has even looked at what
# it was asked to run, so without it every start dies on a Python traceback
# rather than on anything to do with the game.
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

# The base image ships /etc/machine-id empty, and wine reads it on every single
# start: "Failed to read /etc/machine-id, error Invalid argument" in the console
# of every server, every boot, about nothing anyone can act on. The container
# runs as an arbitrary uid and cannot write the file itself, so fill it here.
RUN head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > /etc/machine-id \
    && chmod 0444 /etc/machine-id

# gorcon: the panel console has no other way into this server (Palworld reads
# nothing from stdin) and the graceful stop saves the world over RCON before
# shutting down. Pinned, same version as the shared base.
ARG GORCON_VERSION=0.10.3
RUN curl -fsSL -o /tmp/rcon.tar.gz \
       "https://github.com/gorcon/rcon-cli/releases/download/v${GORCON_VERSION}/rcon-${GORCON_VERSION}-amd64_linux.tar.gz" \
    && tar -xzf /tmp/rcon.tar.gz -C /tmp \
    && install -m 0755 "/tmp/rcon-${GORCON_VERSION}-amd64_linux/rcon" /usr/local/bin/rcon \
    && rm -rf /tmp/rcon.tar.gz "/tmp/rcon-${GORCON_VERSION}-amd64_linux" \
    && /usr/local/bin/rcon --version

# Wings runs the game container as the node's own uid (988, 998, ...), not the
# image's `container` user, and SteamCMD self-updates into its own directory -
# so the tree must be world-rwx for any runtime uid to exec and copy it.
RUN mkdir -p /opt/steamcmd \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
       | tar -xz -C /opt/steamcmd \
    && chmod -R 0777 /opt/steamcmd

# GE-Proton rather than Valve's build: it publishes a self-contained tarball on
# a pinnable tag, whereas Valve's ships as a Steam depot whose version cannot be
# fixed for a reproducible build.
#
# Upstream supports running GE-Proton outside Steam only through umu, whose job
# is to recreate Steam's pressure-vessel container. That container exists to
# reconcile the host's GRAPHICS stack with the runtime's libraries - a headless
# dedicated server touches none of it, which is why calling the launcher
# directly works here and would not for a desktop game.
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

# A wrapper rather than a symlink: the launcher resolves its own toolchain from
# the script's location, and a symlink on PATH would send it looking in
# /usr/local/bin.
RUN printf '#!/bin/sh\nexec python3 /opt/pterohost-proton/proton "$@"\n' > /usr/local/bin/proton \
    && chmod 0755 /usr/local/bin/proton

# RE-UE4SS, staged in the image and copied into Pal/Binaries/Win64 by
# start-palworld (that directory lives in the volume and is rewritten by every
# app_update, so it cannot be baked).
ARG UE4SS_VERSION=v3.0.1
ARG UE4SS_SHA256=4b47d4bceddd2f561a4e395bfa00924ccfc945af576a2d0c613e6537846c57ec

RUN mkdir -p /opt/pterohost/ue4ss/payload \
    && curl -fsSL -o /tmp/ue4ss.zip \
       "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/${UE4SS_VERSION}/UE4SS_${UE4SS_VERSION}.zip" \
    && echo "${UE4SS_SHA256}  /tmp/ue4ss.zip" | sha256sum -c - \
    && unzip -q /tmp/ue4ss.zip -d /opt/pterohost/ue4ss/payload \
    && rm -f /tmp/ue4ss.zip \
    && test -f /opt/pterohost/ue4ss/payload/UE4SS.dll \
    && printf '%s\n' "${UE4SS_VERSION}" > /opt/pterohost/ue4ss/VERSION \
    && chmod -R a+rX /opt/pterohost/ue4ss

# The proxy DLL that actually loads UE4SS on a dedicated server.
#
# RE-UE4SS releases ship dwmapi.dll as their loader, and it is useless here:
# dwmapi is the Desktop Window Manager, which a headless server never imports,
# so the loader is simply never called. Renaming it is not a fix either - the
# game DOES import winmm, and dwmapi.dll exports none of those 181 symbols, so a
# renamed copy stops the server from starting at all.
#
# So the loader has to be a real winmm proxy: RE-UE4SS's own `proxy` project
# built against winmm, forwarding the full winmm surface to the system DLL. The
# binary is vendored rather than fetched at build time so that what we ship is
# what was reviewed.
#
#   provenance: ptero-eggs/game-eggs, palworld/winmm.dll
#               commit 60ef9fbfdac42eef89d656c3f587e96376f90aba (2024-06-14)
#   sha256:     c1b7dcb754f222fa80c2de668c916c1555c8a6c6c09a977de46291644c46aff0
#   verified:   PE32+ DLL, 181 forwarded winmm exports, imports LoadLibraryW,
#               PDB path .../proxy/bin/winmm.pdb - the RE-UE4SS proxy project.
COPY --chmod=644 images/palworld-proton/winmm.dll /opt/pterohost/ue4ss/payload/winmm.dll

ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 \
    USER=container HOME=/home/container \
    STEAMCMD_DIR=/opt/steamcmd \
    XDG_RUNTIME_DIR=/tmp \
    PATH=/usr/local/bin:/opt/steamcmd:/usr/bin:/bin \
    PTEROHOST_IMAGE=palworld_proton \
    PTEROHOST_RUNTIME="Palworld - UE5 dedicated (Windows depot, GE-Proton)" \
    PTEROHOST_STEAM_APP="2394010" \
    PTEROHOST_NOTES="RCON + REST API, RE-UE4SS mod loader" \
    SRCDS_APPID=2394010 \
    PAL_RUNTIME=proton \
    PROTON_DIR=/opt/pterohost-proton \
    PAL_UE4SS_DIR=/opt/pterohost/ue4ss \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="winmm=n,b;d3d9=n,b"

# WINEDLLOVERRIDES is load-bearing, not tuning. Without winmm=n,b wine loads its
# own builtin winmm, the proxy in the game directory is never mapped, and mods
# fail in the one way nobody can debug from the panel: no error, no log line,
# they simply do not run.
#
# d3d9 is the same mechanism for a different proxy. The server-side admin tools
# the mod ecosystem actually uses - PalDefender and its forks - ship a d3d9
# proxy rather than a UE4SS mod, and PalServer-Win64-Shipping.exe does import
# d3d9.dll (verified against the shipped binary's import table), so the proxy is
# mapped as soon as wine is told to prefer the native one. Without the override
# the DLL sits in Pal/Binaries/Win64 and is silently ignored - which is what a
# server owner sees as "the mod is installed and the commands still do nothing".
#
# n,b and not n on both: with no proxy present in the game directory wine falls
# back to its builtin, so a server without mods is unaffected.

WORKDIR /home/container
COPY --chmod=755 shared/entrypoint.sh /entrypoint.sh
COPY --chmod=755 shared/sysinfo.sh /sysinfo.sh
COPY --chmod=755 shared/steam-update.sh /usr/local/lib/pterohost/steam-update.sh
COPY --chmod=755 shared/launch.sh /usr/local/lib/pterohost/launch.sh
COPY --chmod=755 shared/kvconf.sh /usr/local/lib/pterohost/kvconf.sh
COPY --chmod=755 shared/unrealini.sh /usr/local/lib/pterohost/unrealini.sh
COPY --chmod=644 shared/unrealini.awk /usr/local/lib/pterohost/unrealini.awk
COPY shared/motd.txt /motd.txt
COPY shared/nodes.tsv /etc/pterohost/nodes.tsv
COPY --chmod=755 images/palworld/start-palworld /usr/local/bin/start-palworld
# Which egg variable writes which OptionSettings key, and with what formatting.
# The same file as the native image - the settings layer is runtime-independent.
COPY --chmod=644 shared/palworld-keys.tsv /etc/pterohost/palworld-keys.tsv
USER container

# tini without -g on purpose. With -g it forwards Wings SIGTERM to the whole
# process group, so the game gets it at the same instant as the bootstrap and
# dies before the trap can save the world. Without it only the bootstrap is
# signalled and the graceful stop stays in control - which matters more here
# than on the native image, because the stop path also has to reach wineserver.
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/bin/bash","/entrypoint.sh"]
