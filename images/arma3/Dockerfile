# Pterohost Arma 3 dedicated-server image.
#
# The server depot is not anonymous - it needs a Steam account that owns the
# game (STEAM_USER/STEAM_PASS). Arma reserves gameport..gameport+3; only the
# game port is allocated by the panel, and the Steam query lives on +1.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Arma 3"
LABEL org.opencontainers.image.description="Arma 3 dedicated server (Steam app 233780, authenticated depot). amd64 only."

ENV PTEROHOST_IMAGE=arma3 \
    PTEROHOST_RUNTIME="Arma 3 - Real Virtuality" \
    PTEROHOST_STEAM_APP="233780" \
    PTEROHOST_NOTES="query port is gameport+1" \
    STEAMCMD_APPID=233780

COPY --chmod=755 images/arma3/start-arma3 /usr/local/bin/start-arma3

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
