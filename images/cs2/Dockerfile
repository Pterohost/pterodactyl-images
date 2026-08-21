# Pterohost Counter-Strike 2 dedicated-server image.
#
# The one game image here that does NOT build on steamcmd_base. Valve builds
# CS2 against the Steam Runtime 3 container ("sniper") and game/cs2.sh expects
# that environment; running it on plain Debian is unsupported and breaks in
# ways that are painful to diagnose. So this image starts from the official
# sniper platform and installs SteamCMD on top.
#
# SteamCMD is a 32-bit binary, so the i386 architecture is enabled here the
# same way the shared base does it - sniper's apt carries the packages.
#
# amd64 only.
FROM registry.gitlab.steamos.cloud/steamrt/sniper/platform:latest

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Counter-Strike 2 (Steam Runtime 3)"
LABEL org.opencontainers.image.description="Counter-Strike 2 dedicated server (Steam app 730) on the official Steam Runtime 3 sniper platform with SteamCMD. amd64 only."

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl tar gzip locales tzdata tini procps iproute2 \
        lib32gcc-s1 lib32stdc++6 \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && (id container >/dev/null 2>&1 || useradd -m -d /home/container -s /bin/bash container) \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

# Same rationale as the shared base: Wings runs the container under its own uid
# and SteamCMD self-updates into its own directory, so the tree must be
# world-rwx for any runtime uid to exec and copy it.
RUN mkdir -p /opt/steamcmd \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
       | tar -xz -C /opt/steamcmd \
    && chmod -R 0777 /opt/steamcmd

ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 \
    USER=container HOME=/home/container \
    STEAMCMD_DIR=/opt/steamcmd \
    XDG_RUNTIME_DIR=/tmp \
    PATH=/usr/local/bin:/opt/steamcmd:/usr/bin:/bin \
    PTEROHOST_IMAGE=cs2 \
    PTEROHOST_RUNTIME="Counter-Strike 2 - Steam Runtime 3" \
    PTEROHOST_STEAM_APP="730" \
    PTEROHOST_NOTES="sniper platform, RCON" \
    SRCDS_APPID=730

WORKDIR /home/container
COPY --chmod=755 shared/entrypoint.sh /entrypoint.sh
COPY --chmod=755 shared/sysinfo.sh /sysinfo.sh
COPY --chmod=755 shared/steam-update.sh /usr/local/lib/pterohost/steam-update.sh
COPY --chmod=755 shared/launch.sh /usr/local/lib/pterohost/launch.sh
COPY --chmod=755 shared/kvconf.sh /usr/local/lib/pterohost/kvconf.sh
COPY --chmod=755 shared/cvarconf.sh /usr/local/lib/pterohost/cvarconf.sh
COPY --chmod=755 shared/cfgconf.sh /usr/local/lib/pterohost/cfgconf.sh
COPY shared/motd.txt /motd.txt
COPY shared/nodes.tsv /etc/pterohost/nodes.tsv
COPY --chmod=755 images/cs2/start-cs2 /usr/local/bin/start-cs2
USER container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
