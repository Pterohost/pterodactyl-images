# Pterohost Source dedicated-server image (srcds).
#
# Один образ на всё семейство Source: Team Fortress 2, Counter-Strike: Source,
# Day of Defeat: Source, Half-Life 2: Deathmatch, Left 4 Dead 2, Insurgency,
# Black Mesa. Игра выбирается парой SRCDS_APPID и SRCDS_GAME - у них общий
# srcds_run и общий набор флагов, отдельный образ на каждую был бы копией.
#
# Главное отличие от апстримного egg «Custom Source Engine Game»: число слотов
# задаётся клиентом. В апстриме -maxplayers нет ни в строке запуска, ни среди
# переменных, поэтому сервер молча поднимается с дефолтом движка (24 у TF2), а
# режимы, которым нужно 32 слота, не стартуют вовсе.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Source (srcds)"
LABEL org.opencontainers.image.description="Source dedicated server: TF2, CS:S, DoD:S, HL2:DM, Left 4 Dead 2, Insurgency, Black Mesa. Слоты, карта, тикрейт и RCON задаются переменными. amd64 only."

USER root

# srcds - 32-битный бинарь, ему нужен полный i386-рантайм поверх того, что
# несёт SteamCMD в базовом образе.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        lib32gcc-s1 lib32stdc++6 libcurl4:i386 libncurses6:i386 libtinfo6:i386 \
        libsdl2-2.0-0:i386 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

COPY --chmod=755 images/source/start-source /usr/local/bin/start-source

ENV PTEROHOST_IMAGE=source \
    PTEROHOST_RUNTIME="Source - srcds (TF2, CS:S, DoD:S, HL2:DM, L4D2, Insurgency, Black Mesa)" \
    PTEROHOST_NOTES="Игра задаётся парой SRCDS_APPID и SRCDS_GAME, слоты - MAX_PLAYERS"

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
