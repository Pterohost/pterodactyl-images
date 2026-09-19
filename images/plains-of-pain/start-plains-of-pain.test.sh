#!/bin/bash
# Test persisted configuration changes and the stop path against a real child.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
source "$repo/images/plains-of-pain/start-plains-of-pain"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
cd "$sandbox"
export SERVER_PORT=37777 QUERY_PORT=37016 MAX_PLAYERS=50 WORLD_NAMESPACE=custom
export SERVER_NAME='A "quoted" name & backslash\test' SERVER_PASSWORD='secret " & \\ $literal'
export ADMIN_ACCOUNT_IDS=12345,4294967295
printf '{"custom":{"keep":true},"mapId":768,"ttr":28800}\n' > server.json
plains_configure server.json
jq -e 'env as $e | .serverName == $e.SERVER_NAME and .password == $e.SERVER_PASSWORD and .custom.keep and .rootNamespace == "custom" and .mapId == 1024 and .ttr == 0 and .port == 37777 and .queryPort == 37016 and .maxPlayers == 50 and (.userdir|endswith("/data"))' server.json >/dev/null
export SERVER_PASSWORD='' ADMIN_ACCOUNT_IDS=''
plains_configure server.json
jq -e '.password == null and .adminAccountIDs == ""' server.json >/dev/null
cp server.json original.json
for assignment in MAX_PLAYERS=256 QUERY_PORT=37777 WORLD_SEED=4294967296 WORLD_SIZE=12 WORLD_NAMESPACE=../escape ADMIN_ACCOUNT_IDS=76561198000000000; do
    if (export "$assignment"; plains_configure server.json) 2>/dev/null; then
        printf 'Invalid setting accepted: %s\n' "$assignment" >&2; exit 1
    fi
    cmp server.json original.json
 done
printf 'invalid JSON\n' > broken.json
if plains_configure broken.json 2>/dev/null; then exit 1; fi
[ "$(cat broken.json)" = 'invalid JSON' ]
# A socket-holding child saves after receiving SIGINT, then exits. The wrapper
# must wait for that save; returning right after kill would race the next boot.
python3 - "$sandbox" <<'PY' &
import pathlib, signal, socket, sys, time
root=pathlib.Path(sys.argv[1]); sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
sock.bind(('127.0.0.1',0)); (root/'port').write_text(str(sock.getsockname()[1]))
def stop(*_):
    time.sleep(.2); (root/'saved').write_text('saved'); sys.exit(0)
signal.signal(signal.SIGINT,stop)
(root/'ready').touch()
while True: time.sleep(.1)
PY
PLAINS_CHILD=$!
for ((i=0;i<100;i++)); do [ ! -f ready ] || break; sleep .02; done
[ -f ready ]
PLAINS_STOPPING=0
plains_stop
[ -f saved ]
! kill -0 "$PLAINS_CHILD" 2>/dev/null
python3 - <<'PY'
import socket,pathlib
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
s.bind(('127.0.0.1',int(pathlib.Path('port').read_text())))
PY
printf 'PASS: JSON preservation, escaping, password clearing, input bounds and graceful save/port release.\n'
