# Space Station 14 server

Image: `ghcr.io/pterohost/pterodactyl-images:ss14` (`linux/amd64`).

The container runs [SS14.Watchdog](https://github.com/space-wizards/SS14.Watchdog),
the vendor's own server wrapper. The watchdog downloads the server build,
starts it, restarts it after a crash or a freeze, and asks it to stop cleanly.
The image bundles the watchdog (built from a pinned upstream commit) and the
.NET 10 / ASP.NET Core 10 runtime; the game server itself is fetched at run time
into the server's volume, so the image does not need rebuilding for a game
update.

## Startup and ports

```text
start-ss14 SS14.Watchdog {{ADDITIONAL_ARGS}}
```

Everything after `SS14.Watchdog` is passed to the **game server** (for example
`--cvar game.lobbyenabled=false`). The watchdog needs no flags of its own.

One allocation is enough. The game uses **UDP** on the port for the game
traffic and **TCP** on the same number for its HTTP status API (`/status`,
`/info`), which the launcher needs. The watchdog's own HTTP API listens on
`127.0.0.1:5000` inside the container and is never exposed.

Readiness is the console line `Server Version ... -> Ready`. The stop signal is
`SIGINT` (`^C`) or `SIGTERM`: the watchdog tells the server to exit, waits for
it, and leaves with status 0.

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `SERVER_PORT` | allocation | Game UDP and status TCP port. Provided by the platform. |
| `SERVER_NAME` | `Space Station 14` | Name in the launcher (`game.hostname`). |
| `MAX_PLAYERS` | `30` | Player slots: `game.soft_max_players`; the hard connection cap is a little higher so an administrator can join a full server. |
| `MANIFEST_URL` | official Wizard's Den manifest | Manifest of a fork. Builds follow it on every start. |
| `SERVER_ZIP_URL` | empty | Linux x64 server ZIP of a fork without a manifest. Wins over the manifest. |
| `AUTO_UPDATE` | `1` | `1`: update at start and check for a newer build every `SS14_UPDATE_CHECK_MINUTES` (the server restarts itself at the end of the round). `0`: keep the installed build. |
| `WATCHDOG_TOKEN` | empty | Token of the watchdog's API. Empty: one is generated and kept in `.ss14/api-token`. |
| `DB_ENGINE` | `sqlite` | `sqlite` (in `instances/ss14/data`) or `postgres`. |
| `PG_HOST`, `PG_PORT`, `PG_DATABASE`, `PG_USER`, `PG_PASSWORD` | | PostgreSQL connection when `DB_ENGINE=postgres`. |
| `HUB_ADVERTISE` | `0` | List the server on the public hub. Advertising accepts the hub rules. |
| `HUB_TAGS` | empty | Comma-separated hub tags. |
| `ADMIN_USER` | empty | Account name that receives full host rights on connect (`console.login_host_user`). |
| `ADDITIONAL_ARGS` | empty | Extra server arguments. |

Tuning, all optional: `SS14_GC_HEAP_PERCENT` (default `85`, `off` for the .NET
default), `SS14_GC_MODE` (`auto`, `server`, `workstation`; `auto` picks the
workstation GC on plans of two cores or less), `SS14_FULL_PGO` (`1`; the
vendor's recommended dynamic PGO), `SS14_TIMEOUT_SECONDS` (`180`; how long the
watchdog waits for a sign of life before killing the server),
`SS14_UPDATE_CHECK_MINUTES` (`30`), `SS14_LOG_KEEP_DAYS` (`14`).

The panel's variables are applied as `ROBUST_CVAR_*` environment variables,
which sit above `instances/ss14/config.toml`. That file is created once and is
the owner's: every setting without a panel field belongs there.

## Files

Everything changeable lives in `/home/container`, so the root filesystem can be
read-only and the container may run under any uid:

- `instances/ss14/bin` - the server build;
- `instances/ss14/data` - database, logs, saved data;
- `instances/ss14/config.toml` - server settings;
- `.ss14` - watchdog state and token;
- `.tmp` - scratch space, emptied at every start.

## Switching update source

Pinning the build (`AUTO_UPDATE=0`) or using a ZIP switches the watchdog to its
"Dummy" provider, which never touches `bin/`. The image resets the watchdog's
build record when the kind of source changes, because the two providers store
the record differently.

## Custom content

A prebuilt server cannot carry custom content. A fork builds its own server
with `Content.Packaging server --hybrid-acz --platform linux-x64` and either
publishes a manifest or hosts the resulting ZIP for `SERVER_ZIP_URL`.
