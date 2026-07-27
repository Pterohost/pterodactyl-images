# Pterohost Project Zomboid dedicated-server image.
#
# Built on the shared SteamCMD base. Everything specific to Zomboid lives in
# start-zomboid; see the header there for what it fixes (hardcoded 8 GB heap,
# RCON configuration, graceful save-on-stop).
#
# Zomboid ships its own JRE inside the game files, so no JDK is installed here -
# the bundled jre64 is what the pzexe launcher uses and what the game is tested
# against.
#
# amd64 only - The Indie Stone publishes no arm64 server depot.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Project Zomboid (cgroup-aware heap, RCON, clean save)"
LABEL org.opencontainers.image.description="Project Zomboid dedicated server (Steam app 380870) with the JVM heap derived from the container memory limit, RCON configured from egg variables, and save-on-stop. amd64 only."

USER root

# libpzexe/the bundled JRE want a couple of X/font libs even headless, and the
# game writes its config through iconv-dependent paths.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libfontconfig1 libfreetype6 libxi6 libxrender1 libxtst6 zlib1g \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

ENV PTEROHOST_IMAGE=zomboid \
    PTEROHOST_RUNTIME="Project Zomboid - bundled JRE" \
    PTEROHOST_STEAM_APP="380870" \
    PTEROHOST_NOTES="JVM heap from the memory limit, RCON, save-on-stop" \
    SRCDS_APPID=380870

COPY --chmod=755 images/zomboid/start-zomboid /usr/local/bin/start-zomboid

USER container
WORKDIR /home/container

# tini without -g on purpose. With -g it forwards Wings SIGTERM to the whole
# process group, so the game gets it at the same instant as the bootstrap and
# dies before the trap can save the world. Without it only the bootstrap is
# signalled and the graceful stop below stays in control.
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/bin/bash","/entrypoint.sh"]
