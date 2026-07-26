# Pterohost SteamCMD base image.
#
# Shared foundation for every SteamCMD-based game server we run. Adding a game
# on top of this is a ~30 line Dockerfile plus its start-* bootstrap, instead of
# repeating the SteamCMD/i386/locale/tini boilerplate each time.
#
# Everything the image owns lives OUTSIDE /home/container, because Wings
# bind-mounts the server volume over that path at runtime. Game files, the
# writable SteamCMD copy and any per-server config live in the volume and
# survive restarts.
#
# amd64 only - SteamCMD ships no arm64 build.
FROM debian:12-slim

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost SteamCMD base"
LABEL org.opencontainers.image.description="Shared SteamCMD/tini/locale base for Pterohost game-server images. amd64 only."

ENV DEBIAN_FRONTEND=noninteractive

# The 32-bit runtime is for SteamCMD itself (a 32-bit binary); the game servers
# on top are 64-bit. libjemalloc2 is available for images that want to preload it
# to cut allocator fragmentation on long-running servers.
#
# libnss-wrapper is installed for both architectures on purpose: Wings runs the
# container as an uid with no passwd entry, entrypoint.sh preloads the wrapper by
# soname, and the 32-bit SteamCMD needs the i386 build of it just as much as the
# 64-bit game server needs the amd64 one.
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg tar unzip xz-utils jq file bc \
        locales tzdata tini procps iproute2 lsof net-tools netcat-openbsd telnet \
        lib32gcc-s1 lib32stdc++6 libgcc-s1 libstdc++6 lib32z1 zlib1g \
        libjemalloc2 libsdl2-2.0-0 libatomic1 libpulse0 \
        libnss-wrapper libnss-wrapper:i386 \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && useradd -m -d /home/container -s /bin/bash container \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

# gorcon: the console bridge for games that do not read stdin (7 Days To Die
# speaks telnet, Palworld speaks Source RCON) and the graceful-stop path for
# games that need a "save" command before shutdown. Pinned so an upstream
# release cannot silently change behaviour on a rebuild.
ARG GORCON_VERSION=0.10.3
RUN curl -fsSL -o /tmp/rcon.tar.gz \
       "https://github.com/gorcon/rcon-cli/releases/download/v${GORCON_VERSION}/rcon-${GORCON_VERSION}-amd64_linux.tar.gz" \
    && tar -xzf /tmp/rcon.tar.gz -C /tmp \
    && install -m 0755 "/tmp/rcon-${GORCON_VERSION}-amd64_linux/rcon" /usr/local/bin/rcon \
    && rm -rf /tmp/rcon.tar.gz "/tmp/rcon-${GORCON_VERSION}-amd64_linux" \
    && /usr/local/bin/rcon --version

# Wings runs the game container as its own uid (e.g. 998), not the image's
# `container` user, and SteamCMD self-updates into its own directory - so the
# tree must be world-rwx for any runtime uid to exec and copy it.
RUN mkdir -p /opt/steamcmd \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
       | tar -xz -C /opt/steamcmd \
    && chmod -R 0777 /opt/steamcmd

ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 \
    USER=container HOME=/home/container \
    STEAMCMD_DIR=/opt/steamcmd \
    JEMALLOC_LIB=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 \
    XDG_RUNTIME_DIR=/tmp \
    PATH=/usr/local/bin:/opt/steamcmd:/usr/bin:/bin \
    PTEROHOST_IMAGE=steamcmd_base \
    PTEROHOST_RUNTIME="SteamCMD base - no game" \
    PTEROHOST_STEAM_APP="-" \
    PTEROHOST_NOTES="shared layer for the game images"

WORKDIR /home/container
COPY --chmod=755 shared/entrypoint.sh /entrypoint.sh
COPY --chmod=755 shared/sysinfo.sh /sysinfo.sh
COPY --chmod=755 shared/steam-update.sh /usr/local/lib/pterohost/steam-update.sh
COPY --chmod=755 shared/launch.sh /usr/local/lib/pterohost/launch.sh
COPY --chmod=755 shared/kvconf.sh /usr/local/lib/pterohost/kvconf.sh
COPY --chmod=755 shared/cfgconf.sh /usr/local/lib/pterohost/cfgconf.sh
COPY --chmod=755 shared/workshop.sh /usr/local/lib/pterohost/workshop.sh
COPY shared/motd.txt /motd.txt
COPY shared/nodes.tsv /etc/pterohost/nodes.tsv
USER container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
