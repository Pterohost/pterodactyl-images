# Pterohost BeamMP server image (multiplayer for BeamNG.drive).
#
# Апстримный egg сервер не ставит вовсе: его установщик ищет ассет релиза по
# шаблону Server-debian / Server-linux, а BeamMP выкладывает файлы вида
# BeamMP-Server.debian.13.x86_64 - совпадений ноль, ссылка на скачивание
# пустая, и в каталог сервера кладётся нерабочий файл.
#
# Здесь ассет выбирается по дистрибутиву самого образа и архитектуре, а не по
# угаданной строке, поэтому смена схемы именования у BeamMP ломает установку
# заметно, а не молча.
#
# amd64 only.
FROM ghcr.io/pelican-eggs/yolks:debian

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost BeamMP"
LABEL org.opencontainers.image.description="BeamMP dedicated server for BeamNG.drive: релиз подбирается под дистрибутив образа, ServerConfig.toml ведётся из панели."

USER root
RUN mkdir -p /usr/local/lib/pterohost
COPY --chmod=755 shared/launch.sh /usr/local/lib/pterohost/launch.sh
COPY --chmod=755 images/beammp/start-beammp /usr/local/bin/start-beammp

ENV PTEROHOST_IMAGE=beammp \
    PTEROHOST_RUNTIME="BeamMP - BeamNG.drive multiplayer" \
    PTEROHOST_NOTES="Ассет релиза подбирается под дистрибутив образа, конфиг - ServerConfig.toml"

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
