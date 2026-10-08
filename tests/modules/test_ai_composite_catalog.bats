#!/usr/bin/env bats

load '../helpers/common'

REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_DISTRO_ID=debian IGOR_DISTRO_FAMILY=debian
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/config"
    cp -a "$REPO_DIR/modules/system" "$REPO_DIR/modules/docker" "$IGOR_DIR/modules/"
    printf 'system=enabled\ndocker=enabled\n' > "$IGOR_DIR/config/modules.conf"
    source "$REPO_DIR/core/lib/module_loader.sh"
    source "$REPO_DIR/core/ai/control.sh"
    _ml_log() { :; }
}

teardown() { teardown_igor_tmpdir; }

_load_real_capability_packages() {
    igor_load_all_modules >/dev/null
    [ "$(igor_module_status system)" = active ]
    [ "$(igor_module_status docker)" = active ]
}

@test "AI catalog exposes real Docker composition when its System children resolve" {
    _load_real_capability_packages
    inspection="$(igor_capability_inspect docker.install)"
    [ "$(printf '%s' "$inspection" | python3 -c 'import json,sys; print(json.load(sys.stdin)["resolution"])')" = resolved ]

    catalog="$(ai_catalog_json)"
    operator="$(igor_operator_surface_seed | python3 "$REPO_DIR/core/lib/operator_surface.py" build)"
    python3 - "$catalog" "$operator" <<'PY'
import json,sys
catalog,surface=map(json.loads,sys.argv[1:])
tool=next(item for item in catalog["tools"] if item["name"]=="run_capability")
assert "docker.install" in tool["openai_params"]["id"]["enum"]
entry=next(row for row in surface["entries"] if row["path"]=="docker.install")
assert entry["availability"]=="active"
PY
}

@test "disabled System child providers keep real Docker composition unavailable" {
    printf 'system=disabled\ndocker=enabled\n' > "$IGOR_DIR/config/modules.conf"
    igor_load_all_modules >/dev/null
    [ "$(igor_module_status docker)" = active ]
    inspection="$(igor_capability_inspect docker.install)"
    [ "$(printf '%s' "$inspection" | python3 -c 'import json,sys; print(json.load(sys.stdin)["resolution"])')" = unavailable ]

    catalog="$(ai_catalog_json)"
    operator="$(igor_operator_surface_seed | python3 "$REPO_DIR/core/lib/operator_surface.py" build)"
    python3 - "$catalog" "$operator" <<'PY'
import json,sys
catalog,surface=map(json.loads,sys.argv[1:])
tool=next((item for item in catalog["tools"] if item["name"]=="run_capability"),None)
ids=set(tool["openai_params"]["id"]["enum"]) if tool else set()
assert "docker.install" not in ids
entry=next(row for row in surface["entries"] if row["target_id"]=="docker.install")
assert surface["availability_model"]=="registration"
assert entry["availability"]=="active", entry
PY
}

@test "unsupported Docker platform family keeps its composition unavailable" {
    export IGOR_DISTRO_ID=fedora IGOR_DISTRO_FAMILY=fedora
    igor_load_all_modules >/dev/null
    [ "$(igor_module_status system)" = active ]
    [ "$(igor_module_status docker)" = unavailable ]

    catalog="$(ai_catalog_json)"
    operator="$(igor_operator_surface_seed | python3 "$REPO_DIR/core/lib/operator_surface.py" build)"
    python3 - "$catalog" "$operator" <<'PY'
import json,sys
catalog,surface=map(json.loads,sys.argv[1:])
tool=next((item for item in catalog["tools"] if item["name"]=="run_capability"),None)
ids=set(tool["openai_params"]["id"]["enum"]) if tool else set()
assert "docker.install" not in ids
entry=next(row for row in surface["entries"] if row["target_id"]=="docker.install")
assert entry["availability"]!="active"
PY
}
