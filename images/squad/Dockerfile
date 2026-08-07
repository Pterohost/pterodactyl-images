# Pterohost Squad dedicated-server image.
#
# Апстримный egg 72 идёт на стоковом steamcmd-образе и не выдаёт серверу
# отдельный порт опроса: в панели он классифицирован в семейство source, где
# дополнительные порты не выделяются вовсе, поэтому QUERY_PORT оставался пустым
# и счётчик игроков не работал ни на одном сервере. Порты чинятся в
# config/port_plan.php, а здесь - всё остальное: конфигурация сервера из
# переменных и корректная остановка.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Squad"
LABEL org.opencontainers.image.description="Squad dedicated server (Steam app 403240): игровой порт, порт опроса и RCON приходят из аллокаций, Server.cfg и Rcon.cfg ведутся переменными."

COPY --chmod=755 images/squad/start-squad /usr/local/bin/start-squad

ENV PTEROHOST_IMAGE=squad \
    PTEROHOST_RUNTIME="Squad - Unreal Engine dedicated server" \
    PTEROHOST_STEAM_APP="403240" \
    PTEROHOST_NOTES="Три порта: игровой, опроса и RCON. Обновление - обычный рестарт, переустановка стирает конфиги" \
    SRCDS_APPID=403240

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
