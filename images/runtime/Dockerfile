ARG BASE_IMAGE=ghcr.io/pelican-eggs/yolks:nodejs_24
FROM ${BASE_IMAGE}

ARG RUNTIME_KIND=node
ARG RUNTIME_TITLE="Node.js"

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost runtime"
LABEL org.opencontainers.image.description="Единый образ под ботов и скрипты: один bootstrap на все рантаймы"

USER root
RUN mkdir -p /usr/local/lib/pterohost
COPY --chmod=755 shared/launch.sh /usr/local/lib/pterohost/launch.sh
COPY --chmod=755 images/runtime/start-runtime /usr/local/bin/start-runtime

ENV PTEROHOST_IMAGE="runtime" \
    PTEROHOST_RUNTIME_KIND="${RUNTIME_KIND}" \
    PTEROHOST_RUNTIME="${RUNTIME_TITLE}" \
    PTEROHOST_NOTES="Боты и скрипты: START_COMMAND перекрывает автозапуск"

USER container
WORKDIR /home/container
