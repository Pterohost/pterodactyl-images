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
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg tar unzip xz-utils jq file bc \
        locales tzdata tini procps iproute2 lsof net-tools \
        lib32gcc-s1 lib32stdc++6 libgcc-s1 libstdc++6 \
        libjemalloc2 libsdl2-2.0-0 \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && useradd -m -d /home/container -s /bin/bash container \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

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
    PTEROHOST_JDK_TAG=steamcmd_base

WORKDIR /home/container
COPY --chmod=755 shared/entrypoint.sh /entrypoint.sh
COPY --chmod=755 shared/sysinfo.sh /sysinfo.sh
COPY --chmod=755 shared/steam-update.sh /usr/local/lib/pterohost/steam-update.sh
COPY --chmod=755 shared/kvconf.sh /usr/local/lib/pterohost/kvconf.sh
COPY shared/motd.txt /motd.txt
COPY shared/nodes.tsv /etc/pterohost/nodes.tsv
USER container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
