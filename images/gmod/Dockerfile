# Pterohost Garry's Mod dedicated-server image.
#
# srcds is a 32-bit binary unless the x86-64 beta branch is selected, which is
# why the shared base carries the i386 runtime. See start-gmod for the launch
# logic.
#
# Built on steamcmd_base_trixie (debian:13, glibc 2.41), not steamcmd_base
# (debian:12, glibc 2.36). On 2026-11-03 Facepunch moved the dev branch to a
# newer toolchain: srcds_linux and every engine .so in build 26393045 need
# GLIBC_2.38, and on the bookworm base every dev server died on start with
# "/lib/i386-linux-gnu/libc.so.6: version `GLIBC_2.38' not found". public and
# x86-64 were still on GLIBC_2.4 that day, but they follow dev, so the image
# moves before they do rather than after 130 servers stop booting.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base_trixie

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Garry's Mod (srcds, strict port bind)"
LABEL org.opencontainers.image.description="Garry's Mod dedicated server (Steam app 4020) with 32-bit and x86-64 beta support, RCON and strict port binding. Debian 13 runtime (glibc 2.41). amd64 only."

USER root

# Source engine pulls in a handful of 32-bit libraries beyond the base set.
# libcurl4t64 is trixie's name for libcurl4 (the 64-bit time_t transition).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        lib32gcc-s1 lib32stdc++6 libcurl4t64:i386 libncurses6:i386 libtinfo6:i386 \
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
