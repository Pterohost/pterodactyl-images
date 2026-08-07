# Pterohost Factorio headless server image.
#
# Апстримные eggs формально работают, но число игроков клиенту недоступно:
# переменная слотов помечена user_editable=0, а панель на каждом старте
# переписывает max_players в data/server-settings.json своим значением. Продавать
# тарифы «на 32 игрока» при этом нечестно.
#
# Здесь настройки сервера ведёт сам образ: server-settings.json создаётся один
# раз, а поля, которыми владеет панель, синхронизируются на каждом запуске -
# остальное остаётся тем, что выставил владелец сервера.
#
# amd64 only.
FROM ghcr.io/pelican-eggs/yolks:debian

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Factorio (headless)"
LABEL org.opencontainers.image.description="Factorio headless server: версия выбирается из stable/experimental или пином, слоты и настройки правит владелец, RCON и белый список включаются флагом."

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends xz-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/local/lib/pterohost
COPY --chmod=755 shared/launch.sh /usr/local/lib/pterohost/launch.sh
COPY --chmod=755 images/factorio/start-factorio /usr/local/bin/start-factorio

ENV PTEROHOST_IMAGE=factorio \
    PTEROHOST_RUNTIME="Factorio - headless" \
    PTEROHOST_NOTES="Слоты и настройки сервера правит владелец, версия задаётся переменной"

USER container
WORKDIR /home/container

# tini без -g: Factorio сохраняет игру по SIGINT, групповой сигнал убил бы его
# раньше, чем он успеет дописать файл.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
