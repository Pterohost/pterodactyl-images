# pterodactyl-images

Container images for [Pterodactyl Panel](https://pterodactyl.io/) maintained by [Pterohost](https://pterohost.com).
Replaces the patchwork of third-party Java images used by Minecraft eggs with a single, multi-arch registry.

Registry: `ghcr.io/pterohost/pterodactyl-images`
Architectures: `linux/amd64`, `linux/arm64`
License: MIT

## Supported tags

| Tag | Runtime | JDK | Default GC | Base | Status |
|---|---|---|---|---|---|
| `java_7` | Azul Zulu 7 | 7 | G1 | debian:bullseye | legacy, frozen |
| `java_8` | Eclipse Temurin 8 | 8 | G1 | ubuntu:jammy | stable |
| `java_11` | Eclipse Temurin 11 | 11 | G1 | ubuntu:jammy | stable |
| `java_16` | Eclipse Temurin 16 | 16 | G1 | ubuntu:focal | EOL, frozen |
| `java_17` | Eclipse Temurin 17 | 17 LTS | Shenandoah | ubuntu:jammy | stable |
| `java_17_graalvm` | GraalVM CE | 17 | G1 | oraclelinux:8 | stable |
| `java_18` | Eclipse Temurin 18 | 18 | G1 | ubuntu:jammy | frozen |
| `java_21` | Eclipse Temurin 21 | 21 LTS | Generational ZGC | ubuntu:jammy | stable |
| `java_21_graalvm` | GraalVM CE | 21 LTS | G1 | oraclelinux:8 | stable |
| `java_24` | Eclipse Temurin 24 | 24 | Generational ZGC | ubuntu:noble | stable |
| `java_24_graalvm` | GraalVM CE | 24 | G1 | oraclelinux:8 | stable |
| `java_25` | Eclipse Temurin 25 | 25 LTS | Generational ZGC | ubuntu:noble | stable |
| `java_25_graalvm` | GraalVM CE | 25 LTS | G1 | oraclelinux:8 | stable |
| `java_26_ea` | BellSoft Liberica | 26 EA | Generational ZGC | debian:bookworm | early access |

> A `java_26_ea_graalvm` tag will be added once GraalVM CE publishes a 26 dev image.

### Game-server tags

| Tag | Runtime | Base | Arch | Notes |
|---|---|---|---|---|
| `sbox` | s&box dedicated server (SteamCMD + Wine) | ubuntu:24.04 | amd64 | Steam app `1892930`, anonymous SteamCMD. See below. |
| `rust` | RustDedicated (native Linux) | debian:12-slim | amd64 | Steam app `258550`, Oxide / Carbon / vanilla. See below. |

The `sbox` tag bundles SteamCMD and Wine and ships a `start-sbox` bootstrap
(downloads/validates the server, symlinks the Steam client SDK, then launches
the server). Use it with a Pterodactyl egg whose startup command is `start-sbox`.
amd64 only - s&box has no ARM build.

The `rust` tag ships a `start-rust` bootstrap for the native Linux RustDedicated
server. Use it with a Pterodactyl egg whose startup command is `start-rust`.
amd64 only - Facepunch publishes no arm64 depot. Per boot it:

- updates the server via anonymous SteamCMD (`STEAM_BRANCH`: `public`, `staging`,
  `aux01`, `aux02`), run from a writable copy inside the server volume;
- installs the selected modding framework deterministically
  (`MODDING_FRAMEWORK`: `oxide`, `carbon` or `vanilla`), detects framework
  switches and restores vanilla assemblies before changing over;
- fetches optional Oxide extensions (`CHAOS_DL`, `DISCORD_EXT`, `RUSTEDIT_EXT`);
- can preload jemalloc to cut memory fragmentation (`USE_JEMALLOC=1`;
  vanilla/Carbon only - it is force-skipped for Oxide, whose compiler it breaks);
- assembles the full RustDedicated argument list from egg variables (ports,
  identity, map/seed/size or `MAP_URL`, tickrate, Rust+ `app.port` with public-IP
  auto-detect, `ADDITIONAL_ARGS` passthrough).

Every network step is non-fatal: a transient CDN or Steam hiccup logs a warning
and boots with existing files instead of leaving the server down.

**Panel console bridge.** RustDedicated does not read stdin, which is where
Wings delivers panel-console input - on images without a bridge every console
command (including the egg stop command `quit`) is silently ignored. The image
bundles a pinned static [websocat](https://github.com/vi/websocat) and
`start-rust` forwards each console line to the server's local WebRCON endpoint,
echoing the command's reply back into the console. If RCON is not up yet,
`quit` falls back to SIGTERM so a panel Stop still shuts the server down
cleanly.

s&box currently only ships an anonymously-installable build on the **Windows**
depot; the native Linux depot returns `Missing configuration` from SteamCMD. So
the default runtime is `RUNTIME_MODE=wine` (Windows build under Wine; the depot
bundles its own .NET). The base is Ubuntu 24.04 (glibc >= 2.38) so that
`RUNTIME_MODE=linux` can run the native binary on this same image once Facepunch
publishes an installable Linux depot.

All tags are multi-arch manifest lists - `docker pull` selects the right layer automatically.
Tags are also published with the commit SHA suffix (`:<tag>-<sha>`) for pinning.

## Comparison

| Registry | JDK range | GraalVM | Multi-arch | Default GC (modern) | Branded entrypoint | Diagnostics |
|---|---|---|---|---|---|---|
| `ghcr.io/pterohost/pterodactyl-images` | 7 - 26 | 4 versions (17, 21, 24, 25) | amd64 + arm64 | Generational ZGC / Shenandoah | yes | CPU, RAM, GC, cgroup-aware |
| `ghcr.io/pterodactyl/yolks` | 8 - 21 | no | amd64 + arm64 | G1 | no | none |
| `ghcr.io/parkervcp/yolks` | 8 - 25 | no | amd64 | G1 | no | none |
| `ghcr.io/rikodev/pterodactyl-graalvm` | 25 only | yes | amd64 | G1 | no | none |

## Quickstart

```bash
# Pull the latest Java 21 image (multi-arch)
docker pull ghcr.io/pterohost/pterodactyl-images:java_21

# Run an interactive shell to inspect the entrypoint output
docker run --rm -it \
  -e STARTUP='java -version' \
  ghcr.io/pterohost/pterodactyl-images:java_21
```

For a Paper server with the Pterodactyl `STARTUP` template:

```bash
docker run -d --name paper-test \
  -p 25565:25565 \
  -e EULA=true \
  -e STARTUP='java -Xms512M -Xmx2G -jar paper.jar nogui' \
  -v $(pwd)/server:/home/container \
  ghcr.io/pterohost/pterodactyl-images:java_21
```

## Pterodactyl integration

Open **Admin -> Nests -> Eggs -> Edit** and append the image to the **Docker Images** list using the
`Display Name|image:tag` syntax:

```
Pterohost Java 21 (Gen ZGC)|ghcr.io/pterohost/pterodactyl-images:java_21
Pterohost Java 21 GraalVM CE|ghcr.io/pterohost/pterodactyl-images:java_21_graalvm
Pterohost Java 25 LTS (Gen ZGC)|ghcr.io/pterohost/pterodactyl-images:java_25
Pterohost Java 25 GraalVM CE|ghcr.io/pterohost/pterodactyl-images:java_25_graalvm
Pterohost s&box (native Linux)|ghcr.io/pterohost/pterodactyl-images:sbox
Pterohost Rust (Oxide/Carbon/vanilla)|ghcr.io/pterohost/pterodactyl-images:rust
```

Bulk replacement of legacy tags in the `eggs.docker_images` JSON column can be done via a single
SQL statement against the panel database:

```sql
UPDATE eggs
SET docker_images = REPLACE(
        docker_images,
        'ghcr.io/rikodev/pterodactyl-graalvm:25-JDK',
        'ghcr.io/pterohost/pterodactyl-images:java_25_graalvm'
);
```

## GC reference

| Workload | Suggested tag | Suggested flag |
|---|---|---|
| Paper / Folia (single instance, big heap) | `java_21` / `java_25` | `-XX:+UseZGC -XX:+ZGenerational` |
| Paper (Java 17 fallback) | `java_17` | `-XX:+UseShenandoahGC` |
| Paper / Folia (CPU-bound, many entities) | `java_21_graalvm` / `java_25_graalvm` | `-XX:+UseG1GC` + Aikar flags |
| Forge / NeoForge (heavy modpack) | `java_21` | `-XX:+UseShenandoahGC` |
| Vanilla, snapshots | `java_25` | `-XX:+UseZGC -XX:+ZGenerational` |
| BungeeCord / Velocity / Waterfall | `java_21` | `-XX:+UseG1GC` (proxy is I/O-bound) |
| Legacy modpacks (1.7 - 1.12) | `java_8` | `-XX:+UseG1GC` |
| 1.4 - 1.6 modpacks | `java_7` | `-XX:+UseParallelGC` |

The image does not force GC flags - they belong in the Pterodactyl egg `STARTUP` template.
`PTEROHOST_GC` env var is set per tag and printed at startup as a hint only.

## Container layout

Every image ships with:

- `container` user, UID/GID auto-assigned, home `/home/container`
- `tini` as PID 1 (clean SIGTERM forwarding to the JVM)
- `en_US.UTF-8` locale, `LANG=en_US.UTF-8`
- Branded entrypoint at `/entrypoint.sh` (expands `${VAR}` tokens from Wings `STARTUP`)
- Diagnostics at `/sysinfo.sh` - prints JDK, CPU model, cgroup CPU quota, cgroup memory limit,
  free disk on `/home/container`, internal IP, hostname

`INTERNAL_IP` is exported for compatibility with eggs that reference it.

## Building locally

```bash
git clone https://github.com/Pterohost/pterodactyl-images
cd pterodactyl-images

# Single-arch sanity build
docker buildx build \
  --platform linux/amd64 \
  -f images/java-21/Dockerfile \
  -t pt-test:21 \
  --load .

docker run --rm -e STARTUP='java -version' pt-test:21
```

For multi-arch the runner needs QEMU emulation (`docker run --privileged --rm tonistiigi/binfmt --install all`).

## Pterohost

[Pterohost](https://pterohost.com) operates Minecraft, proxy and panel hosting nodes powered by the
Pterodactyl ecosystem. This repository is the canonical home of the Docker images used across the
fleet; outside contributions are welcome via pull requests.

## License

MIT - see [LICENSE](LICENSE).
