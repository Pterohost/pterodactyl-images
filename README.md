# pterodactyl-images

Container images for [Pterodactyl Panel](https://pterodactyl.io/) maintained by [Pterohost](https://pterohost.com).
Replaces the patchwork of third-party images used by Pterodactyl eggs with a single registry: a full
multi-arch Java line for Minecraft plus native game-server images for s&box and Rust.

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
| `steamcmd_base` | SteamCMD + tini + locales | debian:12-slim | amd64 | Shared base for the game images below. Not useful on its own. |
| `sbox` | s&box dedicated server (SteamCMD + Wine) | ubuntu:24.04 | amd64 | Steam app `1892930`, anonymous SteamCMD. See below. |
| `rust` | RustDedicated (native Linux) | debian:12-slim | amd64 | Steam app `258550`, Oxide / Carbon / vanilla. See below. |
| `zomboid` | Project Zomboid dedicated server | `steamcmd_base` | amd64 | Steam app `380870`. cgroup-aware JVM heap, RCON, save-on-stop. See below. |
| `palworld` | Palworld dedicated server | `steamcmd_base` | amd64 | Steam app `2394010`. RCON + REST API, perf flags. See below. |
| `gmod` | Garry's Mod (srcds) | `steamcmd_base` | amd64 | Steam app `4020`. **x86-64 branch by default**, RCON, strict port bind. |
| `cs2` | Counter-Strike 2 | steamrt sniper | amd64 | Steam app `730`. On the official Steam Runtime 3 platform. |
| `sevendaystodie` | 7 Days To Die | `steamcmd_base` | amd64 | Steam app `294420`. Telnet console bridge. |
| `valheim` | Valheim (BepInEx-aware) | `steamcmd_base` | amd64 | Steam app `896660`. SIGTERM -> SIGINT so the world saves. |
| `unturned` | Unturned | `steamcmd_base` | amd64 | Steam app `1110390`. |
| `satisfactory` | Satisfactory | `steamcmd_base` | amd64 | Steam app `1690800`. Query interfaces bound to all interfaces. |
| `dayz` | DayZ | `steamcmd_base` | amd64 | Steam app `223350`, **authenticated depot**. Syncs `steamQueryPort`. |
| `arma3` | Arma 3 | `steamcmd_base` | amd64 | Steam app `233780`, **authenticated depot**. |

The `steamcmd_base` tag carries SteamCMD (in `/opt/steamcmd`, world-rwx because
Wings runs the container under its own uid), the 32-bit runtime SteamCMD needs,
`tini`, locales and two helper libraries the game bootstraps source:
`steam-update.sh` (retry-hardened anonymous app update run from a writable copy
inside the volume) and `kvconf.sh` (surgical `key=value` config patching that
leaves keys we do not own untouched). Game images are `FROM` it, so adding a
game is a short Dockerfile plus its `start-*` script.

The `zomboid` tag ships a `start-zomboid` bootstrap. Use it with an egg whose
startup command is `start-zomboid`. Per boot it:

- updates the server via anonymous SteamCMD (non-fatal on failure);
- **rewrites the JVM heap from the container's memory limit.** This is the
  headline fix. `ProjectZomboid64` is an ELF launcher, not a shell script, and
  it reads its JVM arguments only from `ProjectZomboid64.json` - which ships
  with a hardcoded `-Xmx8g` and no `-Xms`. A 4 GB plan therefore runs a JVM that
  believes it may grow to 8 GB and gets OOM-killed by the cgroup, while a 16 GB
  plan silently caps itself at 8. Passing `-Xmx` on the command line does
  nothing, which is why the widespread advice to edit `start-server.sh` has no
  effect. `ZOMBOID_HEAP_PCT` (default 80) and `ZOMBOID_MAX_HEAP_MB` tune it;
  `-Xms` is pinned equal to `-Xmx` so the JVM stops resizing the heap mid-game.
  `ZOMBOID_GC=g1` switches from the vendor ZGC to G1 with a 50 ms pause target.
- writes `DefaultPort`, `UDPPort`, `RCONPort`, `RCONPassword`, `PublicName` and
  `MaxPlayers` into `<server>.ini` from the egg variables, leaving every
  gameplay key the owner tuned alone. RCON matters because Zomboid's A2S reply
  carries **no player names** - RCON `players` is the only way the panel can
  list who is online;
- turns SIGTERM into a `quit` on the game's stdin so the world is saved, waiting
  up to `ZOMBOID_STOP_TIMEOUT` (default 90s) before escalating.

The `palworld` tag ships a `start-palworld` bootstrap. Use it with an egg whose
startup command is `start-palworld`. Per boot it:

- updates via anonymous SteamCMD and runs the egg's own
  `PalworldServerConfigParser` when present, so servers migrating from the
  third-party image keep their existing behaviour;
- enables **RCON** and the **REST API** in `PalWorldSettings.ini` from
  `RCON_PORT` / `REST_PORT` / `ADMIN_PASSWORD`. Palworld answers no Valve A2S on
  any port - verified by sweeping the game port, +1, +2, +24714, `QUERY_PORT`,
  `RCON_PORT` and every allocation on running servers - so these two interfaces
  are the only way to read a server's state. The REST API is the richer of the
  two (player names, ping, level, server FPS, uptime, in-game days);
- applies `-useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS` (opt out
  with `PAL_PERF_FLAGS=0`) and can preload jemalloc with `USE_JEMALLOC=1`;
- saves over RCON before shutting down.

Neither image invents a port: RCON and the REST API are only enabled when the
egg actually allocated one, so nothing ever squats on a port the panel did not
hand out.

### The rest of the game line

All of these replace third-party images the panel could not fix. Each is a
`start-<game>` bootstrap on the shared base; the notable per-game bits:

- **`gmod`** - runs the `x86-64` branch by default; it is not constrained by the
  32-bit address space, which is what a large workshop/addon load actually runs
  into. `USE_64BIT_BETA=0` returns to the 32-bit build for a server that needs a
  32-bit-only binary module. Switching branch makes the next start re-download
  the server files, and if the 64-bit depot does not land the bootstrap falls
  back to `./srcds_run` rather than failing.
  Also adds `-strictportbind`: without it srcds silently walks to
  the next free port when the allocated one is briefly busy, while the panel
  keeps advertising the allocated port - so players cannot connect and the
  status query reads whatever else answers there. Opt out with
  `SRCDS_STRICT_PORT=0`.
- **`cs2`** - the one image not built on `steamcmd_base`. Valve builds CS2
  against the Steam Runtime 3 container and `game/cs2.sh` expects it, so this
  starts from `registry.gitlab.steamos.cloud/steamrt/sniper/platform` with
  SteamCMD installed on top.
- **`sevendaystodie`** - 7DTD does not read stdin; it exposes a telnet control
  port. The image waits for that port (world generation takes minutes, so it
  polls instead of sleeping a fixed amount) and attaches a console bridge, which
  is what makes the panel console two-way and lets the stop command arrive. That
  bridge used to be a shell one-liner in the panel database.
- **`valheim`** - turns SIGTERM into SIGINT, because Valheim only writes the
  world on SIGINT. Loads BepInEx via doorstop only when the preloader is
  actually present, so a vanilla server is unaffected.
- **`unturned`** - straightforward; notably does not pass the egg's
  `GSLToken Not Set` placeholder through as a real token.
- **`satisfactory`** - binds `-multihome=0.0.0.0` so the UDP Lightweight Query
  and the HTTPS API are reachable from outside the container; saves on SIGINT.
- **`dayz`** - writes `steamQueryPort` into `serverDZ.cfg` from the allocated
  `QUERY_PORT`. The shipped template leaves it at the stock 27016, which on a
  shared node usually belongs to a different customer.
- **`arma3`** - Arma reserves `port..port+3` and answers Steam queries on `+1`,
  which the panel does not allocate; nothing to configure, but it explains why a
  server can be invisible when the neighbouring port is taken.

`dayz` and `arma3` need `STEAM_USER`/`STEAM_PASS` - Bohemia gates those server
depots behind an account that owns the game. Everything else installs
anonymously.

### Moving existing servers onto these images

`servers.image` and `servers.startup` are per-server copies taken at creation.
Editing the egg changes what NEW servers get and nothing else - every existing
server keeps running the old image forever. The panel ships a command for the
migration:

```bash
php artisan p:servers:set-image --egg=9 \
    --image=ghcr.io/pterohost/pterodactyl-images:gmod \
    --startup=start-gmod --update-egg          # dry run
php artisan p:servers:set-image ... --apply --sync
```

It never restarts anything: a running server keeps its current container until
someone restarts it.

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
Pterohost Project Zomboid|ghcr.io/pterohost/pterodactyl-images:zomboid
Pterohost Palworld (RCON + REST)|ghcr.io/pterohost/pterodactyl-images:palworld
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
