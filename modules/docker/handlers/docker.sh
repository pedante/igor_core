#!/bin/bash
# Docker module v2 experiment handler.
# This file intentionally contains no package manager, sudo or systemd logic.
# Those belong to Core providers.

# Return Docker runtime information.
docker__observe_status() {
    if ! command -v docker >/dev/null 2>&1; then
        printf '%s\n' '{"status":"ok","result":{"installed":false}}'
        return 0
    fi

    local version
    version="$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"

    DOCKER_VERSION="$version" python3 - <<'PY'
import json, os
print(json.dumps({
    "status": "ok",
    "result": {
        "installed": True,
        "version": os.environ.get("DOCKER_VERSION", "unknown")
    }
}, separators=(",", ":")))
PY
}

# Return container inventory.
docker__observe_containers() {
    if ! command -v docker >/dev/null 2>&1; then
        printf '%s\n' '{"status":"ok","result":{"containers":[],"available":false}}'
        return 0
    fi

    docker ps -a --format '{{json .}}' 2>/dev/null | python3 -c '
import json,sys
items=[]
for line in sys.stdin:
    try:
        items.append(json.loads(line))
    except ValueError:
        pass
print(json.dumps({"status":"ok","result":{"containers":items}},separators=(",",":")))
'
}

# Mutations intentionally remain delegated to future Core adapters.
docker__install() {
    printf '%s\n' '{"status":"error","error":{"code":"delegated","message":"docker installation must use Core package and service providers"}}'
}

docker__restart_container() {
    printf '%s\n' '{"status":"error","error":{"code":"delegated","message":"container lifecycle must use Core capability dispatch"}}'
}
