#!/bin/bash

_docker_request() {
    local expected="$1" request
    IFS= read -r request || return 1
    printf '%s' "$request" | "${IGOR_PYTHON:-python3}" -c '
import json,sys
try:
    value=json.load(sys.stdin)
except ValueError:
    raise SystemExit(1)
if (not isinstance(value,dict) or value.get("api_version") != 2 or
        value.get("contribution_id") != sys.argv[1] or
        not isinstance(value.get("input"),dict)):
    raise SystemExit(1)
print(json.dumps(value["input"],separators=(",",":")))
' "$expected"
}

_docker_error() {
    local code="$1" message="$2"
    DOCKER_CODE="$code" DOCKER_MESSAGE="$message" "${IGOR_PYTHON:-python3}" - <<'PY'
import json,os
print(json.dumps({"status":"error","error":{"code":os.environ["DOCKER_CODE"],
      "message":os.environ["DOCKER_MESSAGE"]}},separators=(",",":")))
PY
}

_docker_container_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]]
}

docker__status() {
    local input version="" daemon=false server=""
    input="$(_docker_request docker.status)" || {
        _docker_error invalid_request "expected docker.status v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _docker_error invalid_request "docker.status takes no inputs"
        return 0
    }

    if ! command -v docker >/dev/null 2>&1; then
        printf '%s\n' '{"status":"ok","result":{"installed":false,"version":"","daemon_accessible":false}}'
        return 0
    fi

    version="$(docker --version 2>/dev/null | head -1 | head -c 128)"
    if command -v timeout >/dev/null 2>&1; then
        server="$(timeout 4 docker info --format '{{.ServerVersion}}' 2>/dev/null | head -1 | head -c 128)"
        [ -n "$server" ] && daemon=true
    fi

    DOCKER_VERSION="$version" DOCKER_DAEMON="$daemon" "${IGOR_PYTHON:-python3}" - <<'PY'
import json,os
print(json.dumps({"status":"ok","result":{
    "installed":True,
    "version":os.environ.get("DOCKER_VERSION","")[:128],
    "daemon_accessible":os.environ.get("DOCKER_DAEMON")=="true",
}},separators=(",",":")))
PY
}

docker__container_list() {
    local input rows count text
    input="$(_docker_request docker.container.list)" || {
        _docker_error invalid_request "expected docker.container.list v2 request"
        return 0
    }
    [ "$input" = '{}' ] || {
        _docker_error invalid_request "docker.container.list takes no inputs"
        return 0
    }

    if ! command -v docker >/dev/null 2>&1; then
        printf '%s\n' '{"status":"ok","result":{"available":false,"count":0,"containers":""}}'
        return 0
    fi
    command -v timeout >/dev/null 2>&1 || {
        _docker_error unavailable "timeout is required for bounded Docker inspection"
        return 0
    }

    rows="$(timeout 5 docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null)" || {
        printf '%s\n' '{"status":"ok","result":{"available":false,"count":0,"containers":""}}'
        return 0
    }
    count="$(printf '%s\n' "$rows" | awk 'NF{n++} END{print n+0}')"
    text="$(printf '%s\n' "$rows" | head -100 | head -c 4096)"
    DOCKER_COUNT="$count" DOCKER_ROWS="$text" "${IGOR_PYTHON:-python3}" - <<'PY'
import json,os
print(json.dumps({"status":"ok","result":{
    "available":True,
    "count":int(os.environ["DOCKER_COUNT"]),
    "containers":os.environ.get("DOCKER_ROWS","")[:4096],
}},separators=(",",":")))
PY
}

docker__container_restart() {
    local input container output
    input="$(_docker_request docker.container.restart)" || {
        _docker_error invalid_request "expected docker.container.restart v2 request"
        return 0
    }
    container="$(printf '%s' "$input" | "${IGOR_PYTHON:-python3}" -c 'import json,sys; print(json.load(sys.stdin).get("container",""))')" || container=""
    _docker_container_name "$container" || {
        _docker_error invalid_request "invalid Docker container name"
        return 0
    }
    command -v docker >/dev/null 2>&1 || {
        _docker_error unavailable "Docker CLI is not installed"
        return 0
    }
    command -v timeout >/dev/null 2>&1 || {
        _docker_error unavailable "timeout is required for bounded Docker administration"
        return 0
    }
    output="$(timeout 20 docker restart "$container" 2>/dev/null | head -1 | head -c 128)" || {
        _docker_error failed "Docker container restart failed"
        return 0
    }
    DOCKER_CONTAINER="$container" DOCKER_OUTPUT="$output" "${IGOR_PYTHON:-python3}" - <<'PY'
import json,os
print(json.dumps({"status":"ok","result":{
    "container":os.environ["DOCKER_CONTAINER"],
    "result":os.environ.get("DOCKER_OUTPUT","")[:128],
}},separators=(",",":")))
PY
}

docker__install() {
    _docker_request docker.install >/dev/null || {
        _docker_error invalid_request "expected docker.install v2 request"
        return 0
    }
    _docker_error delegated "docker.install requires System package/service capabilities; Docker does not own apt, pacman or systemd"
}
