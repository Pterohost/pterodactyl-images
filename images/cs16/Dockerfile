FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Counter-Strike 1.6 (ReHLDS)"
LABEL org.opencontainers.image.description="GoldSrc dedicated server on ReHLDS with Metamod and AMX Mod X support"

USER root
# GoldSrc - 32-битный движок: без i386-рантайма hlds_linux не стартует, а на
# steamcmd_base стоят только те 32-битные библиотеки, которые нужны самому SteamCMD.
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        libstdc++6:i386 \
        libcurl4-gnutls-dev:i386 \
        zlib1g:i386 \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 images/cs16/start-cs16 /usr/local/bin/start-cs16

ENV PTEROHOST_IMAGE="cs16" \
    PTEROHOST_RUNTIME="Counter-Strike 1.6 - ReHLDS (GoldSrc)" \
    PTEROHOST_STEAM_APP="90" \
    PTEROHOST_NOTES="Metamod и AMX Mod X ставятся при старте по флагам"

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
