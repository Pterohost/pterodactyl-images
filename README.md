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
| `palworld_proton` | Palworld, **Windows depot under GE-Proton** | `steamcmd_base` | amd64 | Steam app `2394010`. Same bootstrap as `palworld` plus RE-UE4SS. **Slower than the native tag - take it only for mods.** See below. |
| `gmod` | Garry's Mod (srcds) | `steamcmd_base` | amd64 | Steam app `4020`. **x86-64 branch by default**, RCON, strict port bind. |
| `gmod_classic` | Garry's Mod (srcds) | `ghcr.io/pterodactyl/games:source` | amd64 | Upstream image plus a `start-gmod` that runs the startup command verbatim. No image-side tuning - the compatibility fallback for `gmod`. |
| `cs2` | Counter-Strike 2 | steamrt sniper | amd64 | Steam app `730`. On the official Steam Runtime 3 platform. |
| `sevendaystodie` | 7 Days To Die | `steamcmd_base` | amd64 | Steam app `294420`. Telnet console bridge. |
| `valheim` | Valheim (BepInEx-aware) | `steamcmd_base` | amd64 | Steam app `896660`. SIGTERM -> SIGINT so the world saves. |
| `unturned` | Unturned | `steamcmd_base` | amd64 | Steam app `1110390`. |
| `satisfactory` | Satisfactory | `steamcmd_base` | amd64 | Steam app `1690800`. Query interfaces bound to all interfaces. |
| `dayz` | DayZ | `steamcmd_base` | amd64 | Steam app `223350`, **authenticated depot**. Syncs `steamQueryPort`. |
| `arma3` | Arma 3 | `steamcmd_base` | amd64 | Steam app `233780`, **authenticated depot**. |
| `cs16` | Counter-Strike 1.6 (ReHLDS) | `steamcmd_base` | amd64 | Steam app `90`. ReHLDS engine swap, optional Metamod and AMX Mod X. |
| `source` | Source dedicated server (srcds) | `steamcmd_base` | amd64 | TF2, CS:S, DoD:S, HL2:DM, Left 4 Dead 2, Insurgency, Black Mesa. Game picked by `SRCDS_APPID` + `SRCDS_GAME`. Unlike the upstream egg, **slots are settable** (`MAX_PLAYERS`), plus tickrate, SourceTV and hidden GSLT/RCON. |
| `terraria` | Terraria: vanilla, TShock, tModLoader | `ghcr.io/pelican-eggs/yolks:dotnet_9` | amd64 | Not a Steam app. Ships .NET 8 **and** 9 - TShock 6.1 needs 9, tModLoader is built for 8. Core picked by `TERRARIA_CORE`. |
| `barotrauma` | Barotrauma dedicated server | `steamcmd_base` | amd64 | Steam app `1026340`. Writes the allocated port into `serversettings.xml` (root attributes) - upstream left every server on 27015. Caps players at the engine limit of 16. |
| `squad` | Squad dedicated server | `steamcmd_base` | amd64 | Steam app `403240`, ~14 GB download. Game, query and RCON ports all come from allocations - upstream classified Squad into the `source` port family, which hands out none of the extras, so the player counter could never work. |
| `steam_generic` | Generic SteamCMD dedicated server | `steamcmd_base` | amd64 | For games that only need "install app id, run binary with a port". Depot, binary path, port argument style (`-port N` / `Port=N` / `+port N`) and stop signal come from egg variables. Games needing more get their own image. |
| `eco` | Eco dedicated server | `steamcmd_base` | amd64 | Steam app `739590`. Ships `libgdiplus` **and** `libicu` - without the latter .NET refuses to start at all. Port lives only in `Configs/Network.eco`. Falls back to `-offline` with a clear log line when the owner has no Eco account. |
| `starbound` | Starbound dedicated server | `steamcmd_base` | amd64 | Steam app `533830`, **not available anonymously** (`No subscription`) - needs an account that owns the game. Port lives in `storage/starbound_server.config`, which the image creates before first boot. |
| `beammp` | BeamMP (BeamNG.drive multiplayer) | `ghcr.io/pelican-eggs/yolks:debian` | amd64 | Release asset picked by the image's own distro (`debian.13.x86_64`), which is why the upstream `Server-debian` glob installed nothing. Config is `ServerConfig.toml`, written by the image. Listens on `::` (`BEAMMP_BIND_IP`): 3.9.x casts the peer address to IPv6 unconditionally, so an IPv4-only bind rejects every join with `bad address cast`. |
| `factorio` | Factorio headless | `ghcr.io/pelican-eggs/yolks:debian` | amd64 | Version from `stable`/`experimental`/pin. Player slots, admin list and whitelist are the owner's to change - upstream locked the slot variable. SIGTERM becomes SIGINT so the game saves. |

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
  effect. `-Xmx` is the plan (`SERVER_MEMORY`) and `-Xms` is 128 MB, the same
  arithmetic the Minecraft eggs use: Wings gives the container the plan plus a
  5% overhead, which is the room the JVM needs outside the heap. `-Xms` used to
  equal `-Xmx`, so the JVM committed the whole plan in the first second and the
  panel showed a server at 84-96% memory before anyone joined - customers read
  that as "out of RAM" and a node carrying three 24 GB worlds really did run
  out. `ZOMBOID_MIN_HEAP_MB` (default 128), `ZOMBOID_HEAP_PCT` (default 100) and
  `ZOMBOID_MAX_HEAP_MB` tune it. The collector is **G1 by default** - a 50 ms
  pause target plus a periodic collection, without which a G1 heap started small
  would ratchet up and never come back down. `ZOMBOID_GC=zgc` opts back in to
  the vendor ZGC, which on Build 42 is a trap: ZGC backs its heap with a shared
  mapping the cgroup charges as `shmem`, and it fills to the whole `-Xmx` within
  seconds of boot regardless of `-Xms`. A 6 GB B42 server measured 5226 MB of
  `shmem` against `-Xmx5222m` - 97% of the limit - and looped on
  `Memory cgroup out of memory: Killed process (ProjectZomboid6)` with nothing
  in the game log, only exit 137 and a wings "crashed state". The same server on
  G1: 2.8 GB of 6 GB, `shmem` 4 MB, no OOM kill;
- writes `DefaultPort`, `UDPPort`, `RCONPort`, `RCONPassword`, `PublicName` and
  `MaxPlayers` into `<server>.ini` from the egg variables, leaving every
  gameplay key the owner tuned alone. RCON matters because Zomboid's A2S reply
  carries **no player names** - RCON `players` is the only way the panel can
  list who is online;
- **preloads `libjsig.so` by absolute path**, chosen from whichever layout the
  bundled JRE actually has on disk - `jre64/lib/amd64/` on Build 41, and
  `jre64/lib/` on the Zulu 25 JRE current builds ship, which has no `amd64`
  directory at all. Preloading it by bare name instead relies on
  `LD_LIBRARY_PATH`, which only ever named the B41 path, so ld.so answered
  `object 'libjsig.so' from LD_PRELOAD cannot be preloaded ... : ignored` on
  every exec whose binary carries no RUNPATH into the JRE. `jre64/bin/java`
  does carry one, so the JVM loaded it anyway and only the pzexe ELF launcher
  failed - two alarming error lines per boot on every Zomboid console, for a
  preload that was in fact working. An absolute path depends on neither
  `LD_LIBRARY_PATH` nor anybody's RUNPATH;
- turns SIGTERM into a `quit` on the game's stdin so the world is saved, waiting
  up to `ZOMBOID_STOP_TIMEOUT` (default 90s) before escalating. The console
  forwarder that carries `quit` reads from a saved copy of stdin (`exec 4<&0`):
  a background job gets `/dev/null` for stdin unless it is redirected, so the
  earlier `while read; done &` exited instantly and every panel console command
  - including the stop - was swallowed, leaving Wings to SIGKILL the server with
  the world unsaved.

The `palworld` tag ships a `start-palworld` bootstrap. Use it with an egg whose
startup command is `start-palworld`. Per boot it:

- updates via anonymous SteamCMD;
- **owns `PalWorldSettings.ini`.** Every setting lives in one Unreal tuple, and
  `shared/unrealini.awk` walks it key by key rather than splitting on commas -
  which is what the third-party `PalworldServerConfigParser` did, ending the
  replaced value at the first comma after the key. Any name or description
  containing a comma therefore grew one duplicated tail per boot until the
  quotes stopped balancing; two live servers had been rewriting themselves for
  weeks and one was cut off mid-value with no closing parenthesis. The parser is
  no longer run (`PAL_LEGACY_PARSER=1` brings it back) and a damaged tuple is
  repaired on the way past. Which variable writes which key is declared in
  `shared/palworld-keys.tsv`;
- **moves `WorldOption.sav` aside.** When a world is uploaded from the client,
  Palworld takes its settings from `Pal/Saved/SaveGames/0/<id>/WorldOption.sav`
  and ignores `PalWorldSettings.ini` entirely - including `AdminPassword`, which
  then stays EMPTY. Seven servers on our fleet were in that state: the panel
  showed one admin password while the server accepted a blank one from anyone
  who could reach the RCON port, and no settings change ever took effect. The
  file is renamed, never deleted; `PAL_KEEP_WORLD_OPTION=1` opts out;
- bridges the panel console to RCON, because Palworld reads nothing from stdin.
  The egg's stop command must therefore be `^C`, not a console line;
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

#### `palworld_proton` - the Windows build, for mods only

Palworld's mod ecosystem is RE-UE4SS: a Windows DLL injected into
`PalServer-Win64-Shipping.exe`. There is no Linux equivalent, so a server that
wants mods has to run the Windows depot. That is the whole reason this tag
exists.

**It is not faster.** Proton is a translation layer on a game that is already
brutally single-thread bound, and the native `palworld` tag wins on everything
that is not "can I load a mod". Nobody should switch to this image for
performance.

It is the *same* `start-palworld` script - the settings writer, the
`WorldOption.sav` fix, the RCON console bridge and the save-on-stop path are one
implementation, not two. `PAL_RUNTIME=proton` (set by the Dockerfile, never by
the egg) changes exactly four things:

- **the depot.** `STEAMCMD_PLATFORM=windows` makes SteamCMD pull the Windows
  build. The flag goes in before `+login`; after it, SteamCMD ignores it and
  downloads Linux anyway;
- **the config directory.** Unreal reads the one matching the build it is, so
  the settings go to `Pal/Saved/Config/WindowsServer/`. Writing them to
  `LinuxServer/` fails silently - the server boots on defaults and every panel
  setting looks broken;
- **the launch.** `proton run` with `STEAM_COMPAT_DATA_PATH=/home/container/.proton`
  and `STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/container/.steam`. Both inside the
  volume, so the prefix survives a container rebuild. The egg's startup command
  still names the *native* binary and is not edited: `pterohost_swap_binary`
  replaces it, and logs that it did;
- **the stop.** RCON `Save` + `Shutdown` as always, but the process being waited
  on is the launcher, not the game, so `wineserver -k` backs it up. Without that
  the world would be lost to Wings' SIGKILL 30 seconds later.

`USE_JEMALLOC` and the Steam SDK `LD_LIBRARY_PATH` are skipped here: they are
about loading a Linux ELF, and `LD_PRELOAD` in particular is inherited by every
helper Proton spawns and breaks prefix creation.

**RE-UE4SS** ships in the image and is copied into `Pal/Binaries/Win64` on each
boot - it cannot be baked, because that directory is in the volume and every
`app_update` rewrites it. The copy is keyed on a version stamp and repeats
whenever the files have gone missing, which is what a Steam validate does to
them. `Mods/` is seeded once and then left alone: the owner's mods live there.

The loader is `winmm.dll`, not the `dwmapi.dll` from the RE-UE4SS release.
dwmapi is the Desktop Window Manager, which a headless server never imports, so
the shipped loader is simply never called - and renaming it does not help
either, because the game *does* import winmm and dwmapi.dll exports none of
those 181 symbols, so a renamed copy stops the server booting at all. The
vendored `images/palworld-proton/winmm.dll` is RE-UE4SS's own `proxy` project
built against winmm; its provenance and checksum are recorded in the Dockerfile.
`WINEDLLOVERRIDES="winmm=n,b"` is what makes wine prefer it over its builtin -
without that line mods fail with no error and no log line at all.

**The egg's `done` marker has to change.** Most Palworld eggs use `Setting
breakpad minidump AppID = 2394010`, which comes from the native build's
`steamclient.so` and is **not printed under Proton** - Wings would leave such a
server in "starting" forever. Both builds print `Running Palworld dedicated
server on :<port>`, so that is the marker to use. It also happens to be more
honest on the native build: the breakpad line appears during Steam API init, a
second before the server is actually listening.

```json
{"done": "Running Palworld dedicated server on"}
```

`Pal/Saved/SaveGames` is identical between the two builds, so switching a server
between `palworld` and `palworld_proton` is reversible and needs no conversion.
The first boot after a switch is slow: SteamCMD downloads the other platform's
depot in full.

Upstream supports GE-Proton outside Steam only through umu, whose job is to
recreate Steam's pressure-vessel container. That container exists to reconcile
the host's *graphics* stack with the runtime's libraries, and a headless
dedicated server touches none of it - which is why calling the launcher directly
works here and would not for a desktop game.

### The rest of the game line

All of these replace third-party images the panel could not fix. Each is a
`start-<game>` bootstrap on the shared base; the notable per-game bits:

- **`gmod`** - runs the `x86-64` branch by default; it is not constrained by the
  32-bit address space, which is what a large workshop/addon load actually runs
  into. `USE_64BIT_BETA=0` returns to the 32-bit build for a server that needs a
  32-bit-only binary module. Switching branch makes the next start re-download
  the server files, and if the 64-bit depot does not land the bootstrap falls
  back to `./srcds_run` rather than failing. jemalloc is preloaded on the
  64-bit build (`USE_JEMALLOC=0` to disable) and `SRCDS_THREADS` exposes the job
  system's pool size.

  `gmod_mcore_test` and `sv_parallel_packentities`/`sv_parallel_sendsnapshot`
  are **on by default here** (`GMOD_MCORE=0` / `SV_PARALLEL=0` to roll back).
  Upstream ships both off because they have a long history of crashes and
  prediction errors on GMod specifically - this is a deliberate Pterohost
  default, not a safe upstream one. Source's game loop is single-threaded by
  design; the x86-64 branch lifts the address-space ceiling, not that.

  Also adds `-strictportbind`: without it srcds silently walks to
  the next free port when the allocated one is briefly busy, while the panel
  keeps advertising the allocated port - so players cannot connect and the
  status query reads whatever else answers there. Opt out with
  `SRCDS_STRICT_BIND=0`.
- **`cs2`** - the one image not built on `steamcmd_base`. Valve builds CS2
  against the Steam Runtime 3 container and `game/cs2.sh` expects it, so this
  starts from `registry.gitlab.steamos.cloud/steamrt/sniper/platform` with
  SteamCMD installed on top.
- **`cs16`** - swaps the engine for ReHLDS after the app-90 install, and can add
  Metamod and AMX Mod X on request. Both mod installs find the module **by
  filename** in the unpacked archive rather than trusting a path: the metamod-r
  release zip already carries an `addons/metamod/` prefix and names its module
  `metamod_i386.so`, not `metamod.so`. `cstrike/liblist.gam` is the only thing
  the engine reads to locate the game library, and it is written **only after
  the target has been seen on disk** - a path that is not there is not a
  degraded server, it is `Host_Error: Couldn't get DLL API from !`, exit 255,
  and a line on the customer's volume that outlives every restart. If Metamod
  cannot be installed the bootstrap says so and leaves `dlls/cs.so` in place, so
  the server runs without plugins instead of not running at all; AMX Mod X is
  skipped entirely in that case, since Metamod is what loads it. AMXX comes from
  `amxmodx.org/latest.php` (`base` plus the `cstrike` modules) - the
  `/release/<version>` paths are not stable URLs and 404.
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
Windows Proton Palworld|ghcr.io/pterohost/pterodactyl-images:palworld_proton
```

`palworld` and `palworld_proton` go on the **same** egg, as two entries in that
list - the startup command works unchanged for both, so switching runtimes is
one dropdown. Set the egg's `WINDOWS_INSTALL` variable to `1` alongside the
Proton image and the first install pulls the Windows depot directly; leave it at
`0` and the server still repairs itself on the next boot, just slower.

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

## Launch contract

Game images ship a `start-<game>` bootstrap. It used to own the whole command line, which meant
the egg's startup field read `start-gmod` and nothing else - an owner had no way to see what
their server actually ran with, and the variables they could edit had no visible connection to
the flags they produced.

The command line now lives in the egg, where the panel renders it with values filled in. The
image keeps only the parts a static string cannot express. `shared/launch.sh` implements the
contract; `shared/launch.test.sh` is its test suite (`bash shared/launch.test.sh`).

**1. Pass-through.** Whatever reaches the bootstrap as `"$@"` is the command, unreordered and
unrewritten. `start-gmod ./srcds_run -game garrysmod ...` behaves exactly like running
`./srcds_run` by hand.

**2. Prune.** A flag whose value came out empty is dropped together with that value, as is the
Unreal `-flag=` form. That is what lets optional settings live in the visible line:

```
+host_workshop_collection "{{WORKSHOP_ID}}"
```

**The quotes are load-bearing.** `shared/entrypoint.sh` eval's the startup string, so an
unquoted empty `${WORKSHOP_ID}` disappears during word splitting and the flag swallows whatever
argument follows it. Quoted, it arrives as an explicit empty argument the helper can see.

An image that keeps a third-party entrypoint may not get that far. The upstream Pterodactyl one
resolves `STARTUP` with `eval echo $(...)` before eval'ing the result, which flattens the string
and drops the quotes with it - the empty value is gone and the flag is left dangling.
`pterohost_prune_valueless_flags <keys...>` is the fallback for those images: it takes the list
of optional flags the egg's line carries and drops any of them that ended up with no value. See
`images/gmod-classic/start-gmod`.

**3. Append-if-absent.** The image adds only what it computes (thread counts, binary selection,
auto-detected public IP) or what a flag/value pair cannot carry (boolean switches, credentials,
either/or blocks like Rust's map selection). It adds nothing whose flag is already in the line -
an explicit `-threads 4` from the panel always wins.

Credentials stay out of the egg on purpose: the panel substitutes variable values into the
startup command it displays, so a GSLT or an RCON password written there becomes part of the
shop window for no benefit.

**4. Legacy fallback.** No arguments means an un-migrated server, and the bootstrap builds the
command the old way. Image rollout and panel migration are therefore independent, and a
hand-edited startup command never gets stranded.

**5. Log.** `pterohost_log_cmd` prints the final command on every boot, so what the image
appended on top of the startup string is never a mystery.

New game images follow the same shape:

```bash
. /usr/local/lib/pterohost/launch.sh

args=( ... )                       # legacy base only

pterohost_panel_argv "$@"
if [ "${PTEROHOST_FROM_PANEL}" = "1" ]; then
    pterohost_swap_binary ./stock-name "${BINARY}"
else
    PTEROHOST_ARGS=("${BINARY}" "${args[@]}")
fi

pterohost_append_if_absent -threads -threads "${computed}"

pterohost_log_cmd "${PTEROHOST_ARGS[@]}"
exec "${PTEROHOST_ARGS[@]}"
```

### Classic shells

`gmod_classic` is the compatibility counterpart to `gmod`: the upstream
`ghcr.io/pterodactyl/games:source` image plus a `start-gmod` that runs the startup command
verbatim and does nothing else - no SteamCMD, no branch switching, no allocator, no thread
sizing. It exists because switching a server to the upstream image to escape the branded
image's tuning used to leave it unable to boot at all - the egg's startup names `start-gmod`
and that image has none. Tuning variables it cannot honour are reported at startup rather than
silently ignored.

### User lookups under an arbitrary uid

Wings runs a game container as the node's own uid - 988 on one node, 999 on the next - and that
uid has no line in the image's `/etc/passwd`. Most servers never ask. The Bohemia engine does:
DayZ and Arma 3 call `getpwuid()` during startup and read `pw_dir` straight off the result, so a
NULL means SIGSEGV at offset 0x20, before the first log line and before any `.RPT` exists.

`shared/entrypoint.sh` therefore checks whether the current uid resolves and, when it does not,
writes a passwd/group pair into `/tmp` and preloads `libnss_wrapper.so` by soname - the bare
soname so the loader picks the i386 build for the 32-bit SteamCMD and the amd64 build for the
64-bit server. Images built without the library log a warning and carry on unchanged; a uid that
already resolves skips the whole block.

### Workshop mods (DayZ, Arma 3)

`shared/workshop.sh` owns the mod list and the mods themselves for the two Bohemia images:

- **The list.** Order of precedence is `CLIENT_MODS` (an explicit override), then `MODIFICATIONS`,
  then the workshop ids parsed out of the `MOD_FILE` a player exports from the game launcher.
  The two sources are additive and the result is sorted and de-duplicated, which is the order
  these servers have always run with. The bootstrap passes it as one `-mod=` argument.
  The egg cannot express this as a `{{VAR}}`: half of the list lives inside an uploaded HTML file.
- **The mods.** Anything missing is downloaded, anything Steam reports as newer than the local
  copy is refreshed, `.bikey` files land in `keys/`, and freshly downloaded content is lowercased
  (Windows-built mods, case-sensitive filesystem). Named mods uploaded over SFTP are left alone.
  `DISABLE_MOD_UPDATES=1` skips the sync and boots with what is on disk. A Steam outage is never
  fatal.

`shared/workshop.test.sh` covers the list resolution, including the case that matters most: a
missing `MOD_FILE` must warn on stderr, never into the list itself.

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

# Versioned hooks. Git never enables these on clone, and the one hook here
# strips assistant co-author trailers that some editors append on their own.
git config core.hooksPath .githooks

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

AI: Claude is USED in this project for:
1) Commiting/CI automatization
2) Code audits

## License

MIT - see [LICENSE](LICENSE).
