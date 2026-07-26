# Pterohost Garry's Mod - classic shell.
#
# A deliberate non-fork: the upstream Pterodactyl Source image, unmodified,
# plus the one file it was missing. Servers on egg 9 start with "start-gmod",
# so switching a server to ghcr.io/pterodactyl/games:source to escape the
# branded image's tuning meant it simply failed to boot. This image is that
# escape hatch, made to actually work.
#
# Nothing else is added. No SteamCMD, no jemalloc, no branch switching, no
# thread sizing - see images/gmod-classic/start-gmod.
FROM ghcr.io/pterodactyl/games:source

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Garry's Mod (classic shell)"
LABEL org.opencontainers.image.description="Upstream ghcr.io/pterodactyl/games:source with a start-gmod that runs the panel's startup command verbatim. No image-side tuning - the compatibility counterpart to the branded gmod image."

USER root

ENV PTEROHOST_IMAGE=gmod-classic \
    PTEROHOST_RUNTIME="Garry's Mod - srcds (classic shell)" \
    PTEROHOST_NOTES="no image-side tuning; runs the startup command as written"

COPY --chmod=755 shared/launch.sh /usr/local/lib/pterohost/launch.sh
COPY --chmod=755 images/gmod-classic/start-gmod /usr/local/bin/start-gmod

USER container
WORKDIR /home/container

# Entrypoint and CMD are inherited from the upstream image on purpose - this
# image differs from it by exactly one file.
