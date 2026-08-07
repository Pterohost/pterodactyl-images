# Pterohost Eco dedicated-server image.
#
# На общем образе steam-generic сервер Eco падает: он собран под .NET и тянет
# libgdiplus, которой в базовом образе нет - официальный install.sh от
# разработчиков ставит её отдельно, а без неё сервер валится с
# DllNotFoundException. Плюс одиночный .NET-бандл требует каталога для
# распаковки, иначе не запускается на томе с чужими правами.
#
# Порт у Eco задаётся только в Configs/Network.eco, командную строку он не
# слушает, поэтому конфигурацию ведёт этот образ.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Eco"
LABEL org.opencontainers.image.description="Eco dedicated server (Steam app 739590): libgdiplus в образе, порт и настройки пишутся в Configs/Network.eco, остановка сохраняет мир."

USER root
# libgdiplus - без неё сервер валится с DllNotFoundException, её же ставит
# официальный install.sh. libicu - .NET отказывается стартовать вовсе:
# «Couldn't find a valid ICU package installed on the system», проверено
# запуском на свободной ноде.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgdiplus libc6-dev libicu72 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

COPY --chmod=755 images/eco/start-eco /usr/local/bin/start-eco

ENV PTEROHOST_IMAGE=eco \
    PTEROHOST_RUNTIME="Eco - .NET dedicated server" \
    PTEROHOST_STEAM_APP="739590" \
    PTEROHOST_NOTES="Порт живёт в Configs/Network.eco, остановка по SIGTERM сохраняет мир" \
    SRCDS_APPID=739590 \
    DOTNET_BUNDLE_EXTRACT_BASE_DIR="/home/container/.dotnet_bundle" \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    STEAMCMD_PLATFORM=linux

USER container
WORKDIR /home/container

# tini без -g: сервер дописывает мир по SIGTERM, групповой сигнал убил бы его
# раньше, чем он успеет закрыть базу.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
