# pterohost_netping - network ping on the GMod scoreboard

Only `lua/autorun/pterohost_netping.lua` goes into the image; this README and
the tests stay in the repository. The Lua file is copied into
`garrysmod/addons/` and downloaded by every player's client, so it carries no
comments - documentation lives here.

## Why

The scoreboard shows the engine's ping: the network round trip plus the time
spent waiting for the server tick. On a low tickrate that wait is a large part
of the number, so players see a much higher ping in-game than `ping` shows
from their console.

Lua cannot send ICMP, and anything sent through `net` waits for the same
ticks, so the network part has to be measured outside the engine.

## How

- `start-gmod` copies the addon to `garrysmod/addons/pterohost_netping/` on
  every start and runs `gmod-netping-probe` in the background.
  `PTEROHOST_NETPING=0` removes the addon and skips the probe.
- The addon writes the public IPv4 of every human player to
  `garrysmod/data/pterohost_netping/targets.txt` every 5 s and reads
  `rtt.txt` back.
- The probe pings each target every 5 s and writes
  `<ip> <min_rtt_ms> <unix_ts>`. It uses unprivileged ICMP sockets, so it works
  without `CAP_NET_RAW`; if ICMP is not available it logs one line and exits.
- Every 2 s the addon picks, per player:
  1. a fresh (<= 15 s) ICMP round trip, if there is one;
  2. otherwise the engine ping minus the engine overhead measured on the same
     server from players who do answer ICMP (kept for 10 minutes);
  3. otherwise the engine ping minus `pterohost_netping_tickfactor` server
     ticks.

  The value is kept within `[5, engine ping]`, smoothed as the median of the
  last 5 values and published as the NW2 int `pth_netping`.
- `Player:Ping` is replaced on server and client, so every scoreboard sees the
  same number. The original is available as `Player:EnginePing()`.

## Convars

| Convar | Realm | Default | Meaning |
|---|---|---|---|
| `pterohost_netping` | replicated | 1 | 0 shows the engine ping again, no restart |
| `pterohost_netping_icmp` | server | 1 | 0 ignores ICMP results |
| `pterohost_netping_tickfactor` | server | 1 | ticks subtracted when no ICMP data exists |

## Limits

- Players whose router drops ICMP, or whose address is private, get the
  estimate rather than a measurement.
- The tick wait is real input latency. A higher tickrate lowers what players
  feel; this addon only changes what they see.

## Tests

`bash images/gmod/netping.test.sh` - probe parsing and lifecycle, plus the Lua
logic under luajit with GMod API stubs (`pterohost_netping.test.lua`).
