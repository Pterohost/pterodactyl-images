# Pterohost Valheim dedicated-server image (BepInEx-aware).
#
# See start-valheim: the important bit is turning SIGTERM into the SIGINT
# Valheim actually saves the world on.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Valheim (BepInEx, save-on-stop)"
LABEL org.opencontainers.image.description="Valheim dedicated server (Steam app 896660) with optional BepInEx doorstop and a stop path that saves the world. amd64 only."

ENV PTEROHOST_IMAGE=valheim \
    PTEROHOST_RUNTIME="Valheim - Unity (BepInEx-aware)" \
    PTEROHOST_STEAM_APP="896660" \
    PTEROHOST_NOTES="SIGTERM becomes SIGINT so the world saves" \
    SRCDS_APPID=896660 \
    SteamAppId=892970

# PlayFab Party, which is what -crossplay actually runs on. The game ships the
# native library itself (valheim_server_Data/Plugins/libparty.so) and it links
# against PulseAudio's glib mainloop for Party's voice chat. steamcmd_base
# carries libpulse0 and libpulse-simple0 but NOT libpulse-mainloop-glib0, so the
# dlopen fails, and the only trace of it is one line the game prints before the
# banner - "Failed to open plugin: .../libparty.so" - followed much later by
# "DllNotFoundException: party" out of PartyCSharpSDK.SDK.PartyInitialize.
#
# The failure is silent where it matters: the PlayFab REST layer is pure C# and
# keeps working, so the server logs "Logged in PlayFab user via custom ID" and
# refreshes its entity token every 20 minutes exactly as a healthy one does. The
# only visible symptom is that "begin PlayFab create and join network" repeats
# every 30s forever and the join code stays empty - the server never opens a
# relay socket at all. Measured on srv4169 (ticket #293673): a crossplay server
# on Xbox is unreachable without that code, and no amount of port work fixes it.
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpulse-mainloop-glib0 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

COPY --chmod=755 images/valheim/start-valheim /usr/local/bin/start-valheim

USER container
WORKDIR /home/container

# tini without -g on purpose. With -g it forwards Wings SIGTERM to the whole
# process group, so the game gets it at the same instant as the bootstrap and
# dies before the trap can save the world. Without it only the bootstrap is
# signalled and the graceful stop below stays in control.
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/bin/bash","/entrypoint.sh"]
