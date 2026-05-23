FROM ghcr.io/graalvm/jdk-community-dev:latest-ol8

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Java 26 EA GraalVM CE"
LABEL org.opencontainers.image.description="GraalVM CE 26 Early Access for Pterodactyl. Multi-arch. Not for production."

RUN microdnf update \
    && microdnf install -y \
        ca-certificates curl git iproute lsof openssl procps-ng sqlite \
        fontconfig freetype gzip tar tzdata which \
        glibc-locale-source glibc-langpack-en \
    && microdnf clean all \
    && useradd -m -d /home/container -s /bin/bash container \
    && ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') \
    && curl -fsSL -o /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/v0.19.0/tini-static-${ARCH}" \
    && chmod +x /usr/local/bin/tini

ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 \
    USER=container HOME=/home/container \
    PTEROHOST_JDK_TAG=java_26_ea_graalvm PTEROHOST_GC=G1

WORKDIR /home/container
COPY --chmod=755 shared/entrypoint.sh /entrypoint.sh
COPY --chmod=755 shared/sysinfo.sh /sysinfo.sh
COPY shared/motd.txt /motd.txt
USER container

ENTRYPOINT ["/usr/local/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
