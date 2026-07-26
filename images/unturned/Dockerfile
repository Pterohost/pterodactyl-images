# Pterohost Unturned dedicated-server image.
#
# Unturned is a Unity headless build; it reads stdin, so no console bridge is
# needed. Replaces a third-party Docker Hub image with one we control.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Unturned"
LABEL org.opencontainers.image.description="Unturned dedicated server (Steam app 1110390). amd64 only."

ENV PTEROHOST_IMAGE=unturned \
    PTEROHOST_RUNTIME="Unturned - Unity headless" \
    PTEROHOST_STEAM_APP="1110390" \
    PTEROHOST_NOTES="-" \
    SRCDS_APPID=1110390

COPY --chmod=755 images/unturned/start-unturned /usr/local/bin/start-unturned

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
