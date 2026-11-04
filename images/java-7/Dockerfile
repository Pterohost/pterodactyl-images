# Pterohost Java 7 (Azul Zulu).
#
# azul/zulu-openjdk-debian:7 is frozen on Debian 11 (bullseye). Bullseye left
# Debian security support, its debian-security pool now answers 404, and the
# apt-get install below failed on every build from late October 2026. The JDK
# itself is the last Zulu 7 release and will not change, so it is taken out of
# that image and put on a supported debian:12-slim instead of pinning apt to
# archive.debian.org and shipping an unpatched userland.
#
# amd64 only: Azul never published a Zulu 7 build for arm64, and the upstream
# image is a single amd64 manifest. Building it for arm64 produced an amd64 JDK
# inside an image labelled arm64.
FROM azul/zulu-openjdk-debian:7 AS jdk

FROM debian:12-slim

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Java 7 (Azul Zulu)"
LABEL org.opencontainers.image.description="Legacy JDK 7 (Azul Zulu 7u352) on Debian 12 for Pterodactyl. amd64 only. Suitable for Minecraft 1.4-1.6 modpacks."

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git iproute2 lsof openssl procps sqlite3 \
        fontconfig libfreetype6 locales tar tini tzdata \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -d /home/container -s /bin/bash container

COPY --from=jdk /usr/lib/jvm/zulu7-ca-amd64 /usr/lib/jvm/zulu7-ca-amd64

ENV JAVA_HOME=/usr/lib/jvm/zulu7-ca-amd64 \
    PATH=/usr/lib/jvm/zulu7-ca-amd64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 \
    USER=container HOME=/home/container \
    PTEROHOST_JDK_TAG=java_7 PTEROHOST_GC=G1

RUN java -version

WORKDIR /home/container
COPY --chmod=755 shared/entrypoint.sh /entrypoint.sh
COPY --chmod=755 shared/sysinfo.sh /sysinfo.sh
COPY shared/motd.txt /motd.txt
COPY shared/nodes.tsv /etc/pterohost/nodes.tsv
USER container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
