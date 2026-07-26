# Pterohost Palworld dedicated-server image.
#
# Built on the shared SteamCMD base. See start-palworld for what it does: turn
# on RCON and the REST API (the only ways to read a Palworld server's state -
# it answers no A2S at all), apply the documented performance flags, and stop
# cleanly by saving over RCON first.
#
# amd64 only - Pocketpair publishes no arm64 depot.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Palworld (RCON + REST API, perf threads)"
LABEL org.opencontainers.image.description="Palworld dedicated server (Steam app 2394010) with RCON and the REST API enabled from egg variables and the documented -useperfthreads/-NoAsyncLoadingThread/-UseMultithreadForDS flags. amd64 only."

USER root

# gorcon (used by the graceful-stop path to Save before shutting down) now
# lives in the shared base.

ENV PTEROHOST_JDK_TAG=palworld \
    SRCDS_APPID=2394010

COPY --chmod=755 images/palworld/start-palworld /usr/local/bin/start-palworld

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
