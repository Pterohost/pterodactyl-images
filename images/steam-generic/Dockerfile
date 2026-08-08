# Pterohost generic SteamCMD game image.
#
# Волны 2-4 плана - это семь десятков игр, у которых серверная часть устроена
# одинаково: скачать депо через SteamCMD, положить порт в аргументы или в
# конфигурацию, запустить бинарь, корректно остановить. Писать под каждую свой
# образ значит семьдесят раз повторить один и тот же скрипт и семьдесят раз
# по-разному ошибиться.
#
# Поэтому здесь один образ, который параметризуется переменными egg: депо,
# бинарь, форма записи порта, сигнал остановки. Игра, которой этой формы не
# хватает (собственный лаунчер, конфиг сложнее пары ключей, мосты RCON),
# получает свой образ - как Rust, Palworld, Terraria или Squad.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost generic SteamCMD server"
LABEL org.opencontainers.image.description="Общий образ под игры, которым достаточно SteamCMD и запуска бинаря с портом: депо, путь к бинарю, форма аргументов и сигнал остановки задаются переменными egg."

USER root
# Часть Unity- и Unreal-серверов тянет 32-битные библиотеки и SDL даже в
# headless-режиме, а Mono-игры - libgdiplus. xvfb нужен тем Unity-сборкам,
# которые инициализируют графику до того, как узнают про -batchmode: без
# дисплея они падают на старте. Включается переменной HEADLESS_DISPLAY.
# xauth ставится вместе с ним не для красоты: xvfb-run без него отказывается
# стартовать вообще («xauth command not found»), а зависимостью пакета xvfb он
# не является.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        lib32gcc-s1 lib32stdc++6 libsdl2-2.0-0 libatomic1 libpulse0 xvfb xauth \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

COPY --chmod=755 images/steam-generic/start-steam-generic /usr/local/bin/start-steam-generic

ENV PTEROHOST_IMAGE=steam-generic \
    PTEROHOST_RUNTIME="SteamCMD generic" \
    PTEROHOST_NOTES="Депо, бинарь и форма аргументов задаются переменными egg"

USER container
WORKDIR /home/container

# tini без -g: часть игр сохраняет мир по сигналу, и групповой сигнал убил бы
# их раньше, чем они успеют дописать файл. Кому нужен групповой - тот получает
# свой образ.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
