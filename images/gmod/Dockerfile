# Pterohost Garry's Mod dedicated-server image.
#
# srcds is a 32-bit binary unless the x86-64 beta branch is selected, which is
# why the shared base carries the i386 runtime. See start-gmod for the launch
# logic.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Garry's Mod (srcds, strict port bind)"
LABEL org.opencontainers.image.description="Garry's Mod dedicated server (Steam app 4020) with 32-bit and x86-64 beta support, RCON and strict port binding. amd64 only."

USER root

# Source engine pulls in a handful of 32-bit libraries beyond the base set.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        lib32gcc-s1 lib32stdc++6 libcurl4:i386 libncurses6:i386 libtinfo6:i386 \
        libsdl2-2.0-0:i386 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

ENV PTEROHOST_IMAGE=gmod \
    PTEROHOST_RUNTIME="Garry's Mod - srcds (x86-64 branch)" \
    PTEROHOST_STEAM_APP="4020" \
    PTEROHOST_NOTES="job threads from CPU quota, jemalloc, strict port bind" \
    SRCDS_APPID=4020 \
    USE_64BIT_BETA=1 \
    GMOD_MCORE=1 \
    SV_PARALLEL=1

COPY --chmod=755 images/gmod/start-gmod /usr/local/bin/start-gmod

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
