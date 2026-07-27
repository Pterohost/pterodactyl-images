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

ENV PTEROHOST_IMAGE=palworld \
    PTEROHOST_RUNTIME="Palworld - UE5 dedicated" \
    PTEROHOST_STEAM_APP="2394010" \
    PTEROHOST_NOTES="RCON + REST API, perf threads" \
    SRCDS_APPID=2394010

COPY --chmod=755 images/palworld/start-palworld /usr/local/bin/start-palworld
# Which egg variable writes which OptionSettings key, and with what formatting.
# Kept out of the script so adding a setting is a line here plus a variable on
# the egg.
COPY --chmod=644 shared/palworld-keys.tsv /etc/pterohost/palworld-keys.tsv

USER container
WORKDIR /home/container

# tini without -g on purpose. With -g it forwards Wings SIGTERM to the whole
# process group, so the game gets it at the same instant as the bootstrap and
# dies before the trap can save the world. Without it only the bootstrap is
# signalled and the graceful stop below stays in control.
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/bin/bash","/entrypoint.sh"]
