# Native Linux dedicated server; the free server depot is Steam app 2227360.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Plains of Pain"
LABEL org.opencontainers.image.description="Native Plains of Pain server with allocation-aware JSON configuration, persistent worlds and graceful shutdown."

COPY --chmod=755 images/plains-of-pain/start-plains-of-pain /usr/local/bin/start-plains-of-pain

ENV PTEROHOST_IMAGE=plains_of_pain \
    PTEROHOST_RUNTIME="Plains of Pain - native Linux / Unity" \
    PTEROHOST_STEAM_APP=2227360 \
    PTEROHOST_NOTES="UDP game and Steam query allocations; settings in configs/pterohost.json; worlds in data/main" \
    SRCDS_APPID=2227360 \
    STEAMCMD_PLATFORM=linux

USER container
WORKDIR /home/container
# Only the wrapper receives SIGTERM; it sends SIGINT to Unity and waits for saves.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
