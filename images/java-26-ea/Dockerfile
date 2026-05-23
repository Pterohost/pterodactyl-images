FROM bellsoft/liberica-openjdk-debian:26

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Java 26 EA (Liberica, Generational ZGC)"
LABEL org.opencontainers.image.description="JDK 26 Early Access (BellSoft Liberica) for Pterodactyl. Multi-arch. Not for production."

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git iproute2 lsof openssl procps sqlite3 \
        fontconfig libfreetype6 locales tar tini tzdata \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -d /home/container -s /bin/bash container

ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 \
    USER=container HOME=/home/container \
    PTEROHOST_JDK_TAG=java_26_ea PTEROHOST_GC=ZGC_GEN

WORKDIR /home/container
COPY --chmod=755 shared/entrypoint.sh /entrypoint.sh
COPY --chmod=755 shared/sysinfo.sh /sysinfo.sh
COPY shared/motd.txt /motd.txt
COPY shared/nodes.tsv /etc/pterohost/nodes.tsv
USER container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
