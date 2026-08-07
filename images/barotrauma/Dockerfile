# Pterohost Barotrauma dedicated-server image.
#
# Апстримный egg не доносит до сервера выданный панелью порт: переменных порта у
# него нет, строка запуска ./DedicatedServer -batchmode их не принимает, парсера
# конфигурации нет, а установочный скрипт serversettings.xml не создаёт. Сервер
# в итоге всегда слушает 27015 и 27016 независимо от аллокации - два сервера на
# одной ноде столкнутся, а игроки не подключатся по выданному адресу.
#
# Порт у Barotrauma живёт атрибутом корневого элемента serversettings.xml,
# поэтому его правит этот образ: xml-парсер панели работает с элементами, а не с
# атрибутами корня.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Barotrauma"
LABEL org.opencontainers.image.description="Barotrauma dedicated server (Steam app 1026340): порт из аллокации доходит до сервера, настройки правятся переменными."

COPY --chmod=755 images/barotrauma/start-barotrauma /usr/local/bin/start-barotrauma

ENV PTEROHOST_IMAGE=barotrauma \
    PTEROHOST_RUNTIME="Barotrauma - DedicatedServer (.NET)" \
    PTEROHOST_STEAM_APP="1026340" \
    PTEROHOST_NOTES="Порт и настройки пишутся в serversettings.xml, потолок игроков у движка - 16" \
    SRCDS_APPID=1026340

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
