# Pterohost Space Station 14 image.
#
# SS14.Watchdog (github.com/space-wizards/SS14.Watchdog) is the vendor's own
# server wrapper: it downloads and updates the server build from a manifest,
# restarts a server that crashed or stopped answering, and stops it cleanly.
# The watchdog is a small ASP.NET Core application and the server itself is a
# plain .NET 10 application, so one aspnet runtime image carries both.
#
# The watchdog is built from a pinned upstream commit (tag v1.1) because the
# project publishes no Linux binaries. Nothing else is downloaded at build
# time: the game server comes from the manifest or ZIP the owner chooses, at
# runtime, into the server's own volume.
#
# start-ss14 turns the panel's variables into watchdog and server settings and
# adds the .NET GC ceiling; the command line itself stays in the egg.
#
# amd64 only.
ARG WATCHDOG_REF=d62e1ade00ff7483fd78a6f104fa20cacbd4e0df

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS watchdog
ARG WATCHDOG_REF
RUN curl -fsSL "https://github.com/space-wizards/SS14.Watchdog/archive/${WATCHDOG_REF}.tar.gz" -o /tmp/wd.tar.gz \
    && mkdir /src && tar -xzf /tmp/wd.tar.gz -C /src --strip-components=1 \
    && cd /src \
    && dotnet publish SS14.Watchdog/SS14.Watchdog.csproj -c Release -r linux-x64 --no-self-contained \
        -p:DebugType=None -p:DebugSymbols=false -o /out \
    && test -x /out/SS14.Watchdog && test -f /out/appsettings.yml

FROM mcr.microsoft.com/dotnet/aspnet:10.0

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Space Station 14"
LABEL org.opencontainers.image.description="Space Station 14 server under SS14.Watchdog: manifest or ZIP builds, automatic updates and restarts, tuned .NET GC, SQLite or PostgreSQL. amd64 only."

USER root

# libnss-wrapper: Wings starts the container under a node uid that has no
# passwd line (see shared/entrypoint.sh). iproute2/procps: the entrypoint's and
# sysinfo.sh's probes. unzip/curl: ZIP builds and the update trigger.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip tini tzdata procps iproute2 libnss-wrapper \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/* \
    && (id container >/dev/null 2>&1 || useradd -m -d /home/container -s /bin/bash container)

COPY --from=watchdog /out /opt/ss14-watchdog

RUN mkdir -p /usr/local/lib/pterohost /etc/pterohost
COPY --chmod=755 shared/entrypoint.sh /entrypoint.sh
COPY --chmod=755 shared/sysinfo.sh /sysinfo.sh
COPY --chmod=755 shared/launch.sh /usr/local/lib/pterohost/launch.sh
COPY shared/motd.txt /motd.txt
COPY shared/nodes.tsv /etc/pterohost/nodes.tsv
COPY --chmod=755 images/ss14/start-ss14 /usr/local/bin/start-ss14

ENV PTEROHOST_IMAGE="ss14" \
    PTEROHOST_RUNTIME="Space Station 14 - SS14.Watchdog / .NET 10" \
    PTEROHOST_NOTES="One allocation: UDP game + TCP status on the same port; builds in instances/ss14/bin, settings in instances/ss14/config.toml" \
    DOTNET_ROOT="/usr/share/dotnet" \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_EnableDiagnostics=0 \
    USER=container \
    HOME=/home/container \
    PATH=/opt/ss14-watchdog:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
    SS14_WATCHDOG_DIR=/opt/ss14-watchdog

USER container
WORKDIR /home/container

# tini without -g: the watchdog gets the stop signal and asks the server to
# exit itself; a group signal would hit the server first and look like a crash.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
