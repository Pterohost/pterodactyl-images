# Pterohost 7 Days To Die dedicated-server image.
#
# The interesting part is the telnet console bridge in start-7dtd - 7DTD does
# not read stdin, so without it the panel console is one-way and the stop
# command never arrives.
#
# amd64 only.
FROM ghcr.io/pterohost/pterodactyl-images:steamcmd_base

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost 7 Days To Die (telnet console bridge)"
LABEL org.opencontainers.image.description="7 Days To Die dedicated server (Steam app 294420) with a versioned telnet console bridge instead of a shell one-liner in the panel database. amd64 only."

ENV PTEROHOST_JDK_TAG=sevendaystodie \
    SRCDS_APPID=294420

COPY --chmod=755 images/sevendaystodie/start-7dtd /usr/local/bin/start-7dtd

USER container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["/bin/bash","/entrypoint.sh"]
