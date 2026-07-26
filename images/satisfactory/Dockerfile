# Pterohost Satisfactory dedicated-server image.
#
# Satisfactory answers no A2S; the panel reads it over the UDP Lightweight
# Query API and the HTTPS API, both on the game port. -multihome=0.0.0.0 in
# start-satisfactory is what makes those reachable from outside the container.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Satisfactory"
LABEL org.opencontainers.image.description="Satisfactory dedicated server (Steam app 1690800) with save-on-stop and the query interfaces bound to all interfaces. amd64 only."

ENV PTEROHOST_IMAGE=satisfactory \
    PTEROHOST_RUNTIME="Satisfactory - UE5" \
    PTEROHOST_STEAM_APP="1690800" \
    PTEROHOST_NOTES="query bound to all interfaces, save-on-stop" \
    SRCDS_APPID=1690800

COPY --chmod=755 images/satisfactory/start-satisfactory /usr/local/bin/start-satisfactory

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
