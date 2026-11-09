# Pterohost Vintage Story image.
#
# Two .NET runtimes, because the game moved between them: 1.22 is built for
# .NET 10, 1.21 and older for .NET 8. Servers pinned to an older release keep
# starting on the same image instead of needing a different one picked by hand.
# Only Microsoft.NETCore.App is added - the server needs no ASP.NET and no SDK.
#
# start-vintagestory checks the runtime the installed game asks for, sets the GC
# heap ceiling and adds --reducedthreads on small plans; the command line itself
# stays in the egg.
#
# amd64 only.
FROM ghcr.io/ptero-eggs/yolks:dotnet_10

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Vintage Story"
LABEL org.opencontainers.image.description="Vintage Story dedicated server: .NET 10 and .NET 8 runtimes, runtime picked by the installed game version, tuned GC heap ceiling. amd64 only."

USER root

RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && bash /tmp/dotnet-install.sh --channel 8.0 --runtime dotnet --install-dir /usr/share --no-path \
    && rm -f /tmp/dotnet-install.sh \
    && ls -d /usr/share/shared/Microsoft.NETCore.App/8.* /usr/share/shared/Microsoft.NETCore.App/10.*

RUN mkdir -p /usr/local/lib/pterohost
COPY --chmod=755 shared/launch.sh /usr/local/lib/pterohost/launch.sh
COPY --chmod=755 images/vintagestory/start-vintagestory /usr/local/bin/start-vintagestory

ENV PTEROHOST_IMAGE="vintagestory" \
    PTEROHOST_RUNTIME="Vintage Story - .NET 10 and 8" \
    DOTNET_ROOT="/usr/share/" \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1

USER container
WORKDIR /home/container
