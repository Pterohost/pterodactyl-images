# Pterohost s&box dedicated server image (native Linux runtime).
#
# s&box's dedicated server (Steam AppID 1892930) ships an x86-64 native Linux
# build that runs on .NET. It needs a modern toolchain (glibc >= 2.38 /
# libstdc++ >= 3.4.31), which is why the base is Ubuntu 24.04 (noble) and not
# Debian bookworm. SteamCMD downloads/validates the server into the persistent
# /home/container volume at install/boot time (see start-sbox).
#
# Everything the image provides (SteamCMD, .NET, start-sbox) lives OUTSIDE
# /home/container, because Wings bind-mounts the server volume over that path
# at runtime and would otherwise shadow anything baked there.
FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost s&box (native Linux, SteamCMD + .NET)"
LABEL org.opencontainers.image.description="s&box dedicated server (Steam app 1892930) on a native Linux .NET runtime. amd64 only."

# .NET runtime channels to install (newest first). s&box's native Linux server
# currently targets .NET 10; 9.0 is kept as a roll-forward fallback. Override at
# build time with --build-arg DOTNET_CHANNELS="10.0" once the target is pinned.
ARG DOTNET_CHANNELS="10.0 9.0"

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg locales tar tini tzdata \
        procps iproute2 lsof file xz-utils \
        libc6 libstdc++6 libicu74 zlib1g openssl \
        lib32gcc-s1 lib32stdc++6 libsdl2-2.0-0 \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && useradd -m -d /home/container -s /bin/bash container

# .NET runtime(s) via the official install script, into a system path.
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && for ch in ${DOTNET_CHANNELS}; do \
         bash /tmp/dotnet-install.sh --channel "$ch" --runtime aspnetcore \
             --install-dir /usr/share/dotnet --no-path; \
       done \
    && ln -s /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
    && rm -f /tmp/dotnet-install.sh

# SteamCMD into /opt (writable by the container user so it can self-update).
RUN mkdir -p /opt/steamcmd \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
       | tar -xz -C /opt/steamcmd \
    && chown -R container:container /opt/steamcmd \
    && rm -rf /var/lib/apt/lists/*

ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 \
    USER=container HOME=/home/container \
    DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 \
    STEAMCMD_DIR=/opt/steamcmd \
    PATH=/usr/local/bin:/usr/share/dotnet:/opt/steamcmd:/usr/bin:/bin \
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
