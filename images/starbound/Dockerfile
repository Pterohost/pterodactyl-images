# Pterohost Starbound dedicated-server image.
#
# Общий образ steam-generic этой игре не подходит по двум причинам, и обе
# проверены, а не предположены:
#   1. депо 533830 анонимно не отдаётся - SteamCMD отвечает «No subscription»,
#      поэтому нужен аккаунт, владеющий Starbound (переменные STEAM_USER и
#      STEAM_PASS, как у DayZ и Arma 3);
#   2. порт задаётся только ключом gameServerPort в storage/starbound_server.config,
#      которого после чистой установки ещё нет - его создаёт сам сервер на
#      первом запуске. Образ готовит файл заранее, иначе сервер поднимется на
#      своём порту вместо выданного панелью.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Starbound"
LABEL org.opencontainers.image.description="Starbound dedicated server (Steam app 533830, требует аккаунт с игрой): порт и настройки пишутся в storage/starbound_server.config."

COPY --chmod=755 images/starbound/start-starbound /usr/local/bin/start-starbound

ENV PTEROHOST_IMAGE=starbound \
    PTEROHOST_RUNTIME="Starbound - dedicated server" \
    PTEROHOST_STEAM_APP="533830" \
    PTEROHOST_NOTES="Депо требует аккаунт с игрой, порт живёт в storage/starbound_server.config" \
    SRCDS_APPID=533830

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
