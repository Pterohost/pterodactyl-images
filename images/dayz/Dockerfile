# Pterohost DayZ dedicated-server image.
#
# The server depot is not anonymous - it needs a Steam account that owns the
# game (STEAM_USER/STEAM_PASS). start-dayz also writes steamQueryPort into
# serverDZ.cfg so the game answers on the port the panel actually allocated.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost DayZ (steamQueryPort synced to the allocation)"
LABEL org.opencontainers.image.description="DayZ dedicated server (Steam app 223350, authenticated depot) with the Steam query port kept in step with the panel allocation. amd64 only."

ENV PTEROHOST_IMAGE=dayz \
    PTEROHOST_RUNTIME="DayZ - Enfusion" \
    PTEROHOST_STEAM_APP="223350" \
    PTEROHOST_NOTES="steamQueryPort synced to the allocation" \
    STEAMCMD_APPID=223350

COPY --chmod=755 images/dayz/start-dayz /usr/local/bin/start-dayz

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
