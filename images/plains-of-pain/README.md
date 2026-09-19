# Plains of Pain dedicated server

Image: `ghcr.io/pterohost/pterodactyl-images:plains_of_pain` (`linux/amd64`).
Configure the Pterodactyl startup command and environment using the runtime
settings below, and assign two distinct UDP allocations before starting it.
This repository publishes Docker images; hosting egg definitions are managed
separately.

Installation uses `ghcr.io/pterodactyl/installers:debian` as root because Wings
initially mounts a root-owned installation volume. The unprivileged game image
must not be used as the installer: it cannot create files in a new volume.
The installer downloads SteamCMD over HTTPS and installs its 32-bit runtime.

The free dedicated server is Steam app **2227360**; the game client and Steam
SDK identity are **2218970**. This is the native Linux build, without Wine.
SteamCMD must receive `+@sSteamCmdForcePlatformType linux` **before** login.
On the tested depot, a normal Linux `app_update 2227360 validate` fails with
`Missing configuration`, while explicitly selecting Linux without `validate`
succeeds. Both the installer and bootstrap implement that working path. Updates
run on startup by default; an update failure can use an existing installation,
but a first installation without the game binary fails visibly.

## Configuration and persistence

The visible startup command invokes the real binary:

```text
start-plains-of-pain ./PlainsOfPain.x86_64 -nographics -batchmode -ignorecompilererrors -logFile /dev/stdout -cc -config configs/pterohost.json {{ADDITIONAL_ARGS}}
```

The game applies its JSON configuration **after** its CLI arguments, so the
image writes the allocated ports and editable settings into that JSON. Unknown
JSON keys are retained, malformed JSON is rejected without overwriting it, and
passwords are serialized correctly even when they contain quotes or backslashes.
Clearing the password removes password protection on the next start. The file
is private to the container uid. The vendor's `default.json` and `custom.json`
are deliberately avoided because Steam updates overwrite them.

| Variable | Default | Meaning |
|---|---|---|
| `SERVER_PORT` | main allocation | UDP game transport; provided by Wings |
| `QUERY_PORT` | 27016 | Separate allocated UDP Steam/A2S query port |
| `SERVER_NAME` | Pterohost Plains of Pain | Server browser name |
| `SERVER_PASSWORD` | empty | Optional join password |
| `MAX_PLAYERS` | 10 | 1–200; a protocol limit, not a performance guarantee |
| `WORLD_ID` | 1 | Load this world or generate it if the ID is unused |
| `WORLD_SEED` | 12345 | Unsigned 32-bit world generation seed |
| `WORLD_SIZE` | 11 | 11=S, 21=M, 31=L, 41=XL, 51=XXL |
| `MAP_ID` | 1024 | Wasteland v0.8.20 generation version |
| `DIFFICULTY` | 1 | 0 Tourist, 1 Rookies, 2 True Wastelander, 3 Veteran, 4 Overlord, 255 Custom |
| `ADMIN_ACCOUNT_IDS` | empty | Comma-separated **32-bit Account IDs**, not SteamID64 |
| `WORLD_NAMESPACE` | main | Save namespace under `data/` |
| `AUTO_UPDATE` | 1 | SteamCMD update on startup |
| `SRCDS_BETAID` | empty | Steam branch; empty or public selects stable |
| `VALIDATE` | 0 | Optional verification; shared updater retries without it on the metadata error |
| `AUTO_UPDATE_RESTART` | 0 | Opt-in to the Pterohost panel's running-server update watcher |

Saves, world metadata, custom difficulty, and player data stay in
`/home/container/data/main` by default. The engine log is `data/server.log`;
Unity output is also streamed into the panel console. Back up the entire
`data/` directory and `configs/pterohost.json`. To import an existing save,
stop the server, copy its namespace's `worlds/` and `profiles/` into `data/main/`,
and match its world ID, map ID, and namespace before starting.

The JSON namespace field is **`rootNamespace`**, although the manual describes
the CLI argument as `namespace`. The image writes the field the game reads.
The bundled sample configurations still contain map 768; the August 30, 2026
vendor manual and current executable use map 1024. Existing world IDs load
existing worlds: changing the seed, size or map does not regenerate them.
Select an unused `WORLD_ID` for new world content and retain the old save files.

`-cc` enables **in-game** admin commands for the configured Account IDs. It does
not provide a stdin command console or RCON service. Custom difficulty is set
by selecting `DIFFICULTY=255`, joining as a configured admin, then applying
settings in the game's Main Menu → Settings → Difficulty; the game persists
those settings. This procedure is described by the developer in the
[official pinned guide](https://steamcommunity.com/app/2218970/discussions/0/802341826354881418/).
The image does not provide a Workshop or RCON integration.

## Networking and NAT

Forward the main **UDP game port** and the separate **UDP query port**, using
the **same public and internal port numbers**. Ports need not be consecutive.
The engine listens on all interfaces; binding a public NAT address that is not
assigned to a local interface is neither needed nor supported. Do not add a
pretend `PUBLIC_IP` flag: this game does not read one.

Steam discovers the public address from the server's outbound traffic. On
nodes behind a DDoS edge or NAT, route the game's Steam traffic out through the
same public IPv4 address that forwards the two inbound UDP ports. An inbound
port forward alone cannot correct a different outbound public address. Docker
bridge networking uses matching UDP publishes; host networking still needs
unique allocations per server and matching edge forwarding/SNAT.

A browser entry showing only IP:port usually indicates an unreachable query
port. An entry showing the correct name but rejecting joins points to the game
port. A2S_INFO is served on `QUERY_PORT`; the tested reply reports app ID 0 in
the legacy 16-bit field and game ID 2218970 in the extended field, so do not
reject it solely for lacking a nonzero legacy app ID.

## Shutdown and capacity

Configure the panel stop command as **`^C`**. The wrapper also converts Docker/Wings
SIGTERM into SIGINT, then waits until Unity exits and releases the UDP sockets.
The game saves on SIGINT. `ttr` is set to 0 so the vendor's sample eight-hour
self-exit does not interrupt a server; use panel schedules for planned restarts.
Allow at least 120 seconds for a large world to save before forced termination.

The vendor's bundled `Documentation.pdf` (updated August 30, 2026) recommends:

| Players | RAM | CPU cores |
|---|---|---|
| 10 | 4 GB | 2 |
| 50 | 8 GB | 4–6 |
| 100 | 16 GB | 8–12 |
| 200 | 32 GB | 16 |

These are sizing recommendations. Large worlds and active entities can need
more resources. The current installation occupies about 737 MB before
SteamCMD, worlds and backups; allocate space for all of those and future updates.

## Verification

Run `bash images/plains-of-pain/start-plains-of-pain.test.sh` for configuration
preservation, string escaping, password clearing, bounds checks, malformed JSON
handling, and a real socket-holding child's save-and-stop lifecycle.

On September 19, 2026, Steam app 2227360 installed anonymously and launched
version 0.8.20.29 in an isolated 4 GB / 2 CPU container. A small world reached
`Server Ready`, listened on non-default game/query ports 37777/37016, answered
a challenged A2S_INFO query with the configured name and player limit, and
saved world state on SIGINT with exit status 0. The test measured about 1.04 GB
idle memory with zero players; it is not a loaded capacity benchmark.

The final image also passed the same boot with uid/gid 9876 (absent from the
image passwd database), a read-only root filesystem, and a writable volume plus
`/tmp`. It reloaded world ID 1, reached `Server Ready`, and `docker stop` saved
and exited 0 without an OOM or forced kill. A client gameplay session was not
part of this smoke test. Headless Unity logs unsupported shader messages even
on a successful dedicated-server boot; the ready marker and UDP query are the
reliable readiness checks.

The hosting installation procedure was also validated in the stock root
installer image against a new root-owned mode-0755 volume, without a Docker
user override.
It downloaded the complete native depot and exited 0. Dependencies use
`--no-upgrade` to avoid replacing packages already supplied by the installer;
this also avoids a stale Debian 11 security-mirror upgrade in cached images.
The retry loop recovered a transient Steam `Missing configuration` response.
