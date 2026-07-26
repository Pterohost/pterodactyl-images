# Pterohost Valheim dedicated-server image (BepInEx-aware).
#
# See start-valheim: the important bit is turning SIGTERM into the SIGINT
# Valheim actually saves the world on.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Valheim (BepInEx, save-on-stop)"
LABEL org.opencontainers.image.description="Valheim dedicated server (Steam app 896660) with optional BepInEx doorstop and a stop path that saves the world. amd64 only."

ENV PTEROHOST_IMAGE=valheim \
    PTEROHOST_RUNTIME="Valheim - Unity (BepInEx-aware)" \
    PTEROHOST_STEAM_APP="896660" \
    PTEROHOST_NOTES="SIGTERM becomes SIGINT so the world saves" \
    SRCDS_APPID=896660 \
    SteamAppId=892970

COPY --chmod=755 images/valheim/start-valheim /usr/local/bin/start-valheim

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
