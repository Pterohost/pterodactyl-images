# Pterohost s&box dedicated server image.
#
# s&box's dedicated server (Steam app 1892930) currently only ships an
# installable build on the WINDOWS depot - the native Linux depot has no
# anonymously-installable public/staging configuration yet ("Missing
# configuration" from SteamCMD). So today the server is the Windows build run
# under Wine (the .NET runtime ships self-contained inside the depot, so no
# Windows .NET install in the prefix is needed).
#
# The base is Ubuntu 24.04 (glibc >= 2.38) on purpose: when Facepunch publishes
# an installable Linux depot, RUNTIME_MODE=linux can run the native binary on
# this same base without a base-image swap (see start-sbox).
#
# Everything the image provides (Wine, SteamCMD, start-sbox) lives OUTSIDE
# /home/container, because Wings bind-mounts the server volume over that path
# at runtime. The Wine prefix and server files live in the volume and persist.
FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost s&box (Wine, SteamCMD)"
LABEL org.opencontainers.image.description="s&box dedicated server (Steam app 1892930) - Windows build under Wine. amd64 only. RUNTIME_MODE=linux reserved for the future native depot."

ENV DEBIAN_FRONTEND=noninteractive

# The s&box server is a framework-dependent .NET 10 app; the Windows depot ships
# the runtime only as a Steam redist installer that never runs on Linux. Bake the
# Windows x64 .NET runtime so the apphost finds it under Wine via DOTNET_ROOT
# (set in start-sbox). Roll-forward covers the depot's exact 10.0.x patch.
ARG DOTNET_WIN_URL="https://aka.ms/dotnet/10.0/dotnet-runtime-win-x64.zip"

# Base tooling + WineHQ stable (needs i386 for the 32-bit Wine parts).
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg locales tar tini tzdata unzip \
        procps iproute2 lsof file xz-utils cabextract \
    && install -d -m 0755 /etc/apt/keyrings \
    && wget -qO /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
    && wget -qO /etc/apt/sources.list.d/winehq-noble.sources https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends winehq-stable \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && useradd -m -d /home/container -s /bin/bash container \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

# SteamCMD into /opt. Wings runs the game container as its own uid (e.g. 998),
# not the image's `container` user, and SteamCMD self-updates into its own dir -
# so make the tree world-rwx so any runtime uid can exec and write it.
RUN mkdir -p /opt/steamcmd \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
       | tar -xz -C /opt/steamcmd \
    && chmod -R 0777 /opt/steamcmd

# Windows x64 .NET runtime for the server (run under Wine), pointed to by
# DOTNET_ROOT=Z:\opt\sbox-dotnet at launch. World-readable/traversable so any
# runtime uid can load the framework.
RUN mkdir -p /opt/sbox-dotnet \
    && curl -fsSL "${DOTNET_WIN_URL}" -o /tmp/dotnet-win.zip \
    && unzip -q /tmp/dotnet-win.zip -d /opt/sbox-dotnet \
    && rm -f /tmp/dotnet-win.zip \
    && test -d /opt/sbox-dotnet/shared/Microsoft.NETCore.App \
    && chmod -R a+rX /opt/sbox-dotnet

ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 \
    USER=container HOME=/home/container \
    STEAMCMD_DIR=/opt/steamcmd \
    WINEPREFIX=/home/container/.wine WINEARCH=win64 WINEDEBUG=-all \
    WINEDLLOVERRIDES="icu,icuuc=d" \
    DOTNET_EnableWriteXorExecute=0 DOTNET_TieredCompilation=0 \
    DOTNET_ReadyToRun=0 DOTNET_ZapDisable=1 \
    XDG_RUNTIME_DIR=/tmp \
    PATH=/usr/local/bin:/opt/steamcmd:/usr/bin:/bin \
    PTEROHOST_JDK_TAG=sbox

WORKDIR /home/container
COPY --chmod=755 shared/entrypoint.sh /entrypoint.sh
COPY --chmod=755 shared/sysinfo.sh /sysinfo.sh
COPY shared/motd.txt /motd.txt
COPY shared/nodes.tsv /etc/pterohost/nodes.tsv
COPY --chmod=755 images/sbox/start-sbox /usr/local/bin/start-sbox
USER container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
