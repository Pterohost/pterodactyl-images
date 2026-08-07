# Pterohost Terraria dedicated-server image (Vanilla / TShock / tModLoader).
#
# В образе две среды .NET, и это не запас на будущее: TShock 6.1 требует ровно
# девятую (apphost падает с «You must install or update .NET»), а tModLoader
# собран под восьмую. Апстримные eggs стоят на .NET 6, поэтому tModLoader на
# них при каждой установке докачивает свой рантайм в каталог сервера
# (LaunchUtils/InstallDotNet.sh, около сотни мегабайт), а TShock не стартует
# вовсе. С обеими средами в образе первый старт быстрее и не зависит от
# доступности серверов Microsoft.
#
# amd64 only.
FROM ghcr.io/pelican-eggs/yolks:dotnet_9

LABEL org.opencontainers.image.source="https://github.com/Pterohost/pterodactyl-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Pterohost"
LABEL org.opencontainers.image.title="Pterohost Terraria (Vanilla, TShock, tModLoader)"
LABEL org.opencontainers.image.description="Terraria dedicated server: ванильное ядро, TShock и tModLoader в одном образе, .NET 8 внутри, мир сохраняется при остановке."

USER root
# Вторая среда - только рантайм, без SDK: tModLoader net8.0 на девятке не
# запускается, роллфорвард через мажорную версию сам не происходит.
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && bash /tmp/dotnet-install.sh --channel 8.0 --runtime dotnet --install-dir /usr/share --no-path \
    && rm -f /tmp/dotnet-install.sh

RUN mkdir -p /usr/local/lib/pterohost
COPY --chmod=755 shared/launch.sh /usr/local/lib/pterohost/launch.sh
COPY --chmod=755 images/terraria/start-terraria /usr/local/bin/start-terraria

ENV PTEROHOST_IMAGE="terraria" \
    PTEROHOST_RUNTIME="Terraria - .NET 8 и 9 (Vanilla / TShock / tModLoader)" \
    PTEROHOST_NOTES="Ядро выбирается переменной TERRARIA_CORE, мир сохраняется по команде exit" \
    DOTNET_ROOT="/usr/share" \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_BUNDLE_EXTRACT_BASE_DIR="/home/container/.dotnet_bundle"

USER container
WORKDIR /home/container

# tini без -g: остановку ведёт сама игра - Wings отправляет в консоль «exit»,
# сервер сохраняет мир и выходит сам. Групповой сигнал убил бы его раньше.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
