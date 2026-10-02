#!/usr/bin/env bats
# Boundary 2 canonical dispatch with an isolated existing-layout Docker fixture.
load '../helpers/common'
REPO_DIR="${BATS_TEST_DIRNAME}/../.."

setup() {
    setup_igor_tmpdir
    export IGOR_DATA_DIR="$IGOR_DIR/data" _IGOR_LOADER_DIR="$REPO_DIR" REPO_DIR
    mkdir -p "$IGOR_DIR/modules" "$IGOR_DIR/bin" "$IGOR_DIR/application/config" "$IGOR_DIR/application/data"
    cp -a "$REPO_DIR/modules/nextcloud_docker" "$IGOR_DIR/modules/nextcloud_docker"
    export ATTACHMENT_FIXTURE="$IGOR_DIR/container.json" ATTACHMENT_TRACE="$IGOR_DIR/docker.trace"
    export ATTACHMENT_CONFIG="$IGOR_DIR/application/config/config.php"
    printf '<?php /* unchanged existing fixture */\n' > "$ATTACHMENT_CONFIG"
    printf 'nextcloud_docker=enabled\n' > "$IGOR_DIR/config/modules.conf"
    python3 - "$ATTACHMENT_FIXTURE" "$IGOR_DIR/application" <<'PY'
import json,sys
json.dump({'Id':'a'*64,'Name':'/existing-nc','Created':'2025-01-02T03:04:05Z',
 'Image':'sha256:'+'b'*64,'Config':{'Image':'nextcloud:apache','Env':['MYSQL_PASSWORD=NEVER_IMPORT'],
 'Labels':{'com.docker.compose.project':'brownfield','com.docker.compose.service':'app'}},
 'Mounts':[{'Type':'bind','Source':sys.argv[2],'Destination':'/var/www/html'}]},open(sys.argv[1],'w'))
PY
    cat > "$IGOR_DIR/bin/docker" <<'PY'
#!/usr/bin/env python3
import json,os,sys
args=sys.argv[1:]
with open(os.environ['ATTACHMENT_TRACE'],'a') as f: f.write(json.dumps(args)+'\n')
with open(os.environ['ATTACHMENT_FIXTURE']) as f: row=json.load(f)
if args==['info','--format','{{json .}}']: print(json.dumps({'ID':'fixture-daemon'}))
elif args==['ps','-a','--no-trunc','--format','{{json .}}']:
 print(json.dumps({'ID':row['Id'],'Names':'existing-nc','Image':'nextcloud:apache'}))
elif args==['inspect',row['Id']]: print(json.dumps([row]))
elif args==['exec','--user','www-data',row['Id'],'stat','--format=%F|%i|%s|%Y','--','/var/www/html/config/config.php']:
 st=os.lstat(os.environ['ATTACHMENT_CONFIG']); print(f'regular file|{st.st_ino}|{st.st_size}|{int(st.st_mtime)}')
else: sys.exit(97)
PY
    chmod 700 "$IGOR_DIR/bin/docker"
    export PATH="$IGOR_DIR/bin:$PATH"
    stub_ui
    _ml_log() { :; }
    source "$REPO_DIR/core/lib/module_loader.sh"
    igor_load_all_modules >/dev/null
    source "$REPO_DIR/core/ai/safety.sh"
    ai_unscrub_inbound() { printf '%s' "$1"; }
    ai_knowledge_mark_changed() { :; }
    _ai_validate_tool_call() { printf 'BLOCKED: false\n'; }
    ai_mode=executive
}

_invoke_metadata() {
    local ident="$1" document="$2" answer="${3:-y}" payload
    payload="$(python3 - "$ident" "$document" <<'PY'
import json,sys
print(json.dumps({'tool':'run_capability','id':sys.argv[1],'inputs':{'proposal':sys.argv[2]}}))
PY
)"
    printf '%s\n' "$answer" | ai_execute_tool "$payload"
}

_initialize() {
    _invoke_metadata core.deployments.initialize '{}' >/dev/null
    [ "$(python3 "$REPO_DIR/core/lib/deployments.py" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["availability"])')" = available ]
}

_proposal() {
    _igor_attachment_call propose '{"locator":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
}

@test "Executive initialization still requires explicit approval and records the actual requirement" {
    run _invoke_metadata core.deployments.initialize '{}' n
    [ "$status" -eq 0 ]
    [[ "$output" == *'"approval_status":"denied"'* ]]
    [ ! -e "$IGOR_DATA_DIR/deployments/store.sqlite3" ]
    _initialize
    igor_history_cli recent 1 | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; assert r["approval"]=={"requirement":"change_confirm","result":"approved"}; assert r["verification"]["status"]=="passed"'
    [ ! -e "$ATTACHMENT_TRACE" ]
}

@test "canonical adoption and bounded release retain unchanged application and inspectable evidence" {
    _initialize
    before="$(sha256sum "$ATTACHMENT_CONFIG" "$ATTACHMENT_FIXTURE")"
    proposal="$(_proposal)"
    run _invoke_metadata core.deployments.adopt "$proposal"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"success"'* ]] || { printf '%s\n' "$output" >&3; return 1; }
    deployment_id="$(python3 "$REPO_DIR/core/lib/deployments.py" list | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["identity"]["reference"]["object_id"])')"
    view="$(python3 "$REPO_DIR/core/lib/deployments.py" inspect "$deployment_id")"
    python3 - "$view" <<'PY'
import json,sys
r=json.loads(sys.argv[1]); assert len(r['resources'])==4 and len(r['relationships'])==7
assert [(g['duty'],g['setting_id']) for g in r['responsibilities']]==[('configuration','nextcloud_docker.loglevel')]
assert r['observations']['availability']=='not_supplied'
e=next(e for e in r['history']['operations'] if e['capability']['id']=='core.deployments.adopt')
assert e['approval']['result']=='approved' and e['verification']['status']=='passed'
assert len(e['inputs']['proposal_sha256'])==64
assert e['inputs']['proposal']['inspection']['native']['native_id']=='a'*64
assert 'NEVER_IMPORT' not in json.dumps(r)
PY
    fields="$(python3 - "$deployment_id" <<'PY'
import json,sys
print(json.dumps({'deployment_id':sys.argv[1]}))
PY
)"
    release="$(_igor_attachment_call release-propose "$fields")"
    run _invoke_metadata core.deployments.release "$release"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome":"success"'* ]] || { printf '%s\n' "$output" >&3; return 1; }
    python3 "$REPO_DIR/core/lib/deployments.py" inspect "$deployment_id" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["identity"]["lifecycle"]=="known"; assert r["responsibilities"][0]["lifecycle"]=="released"; assert len(r["resources"])==4; assert r["detach"]["status"]=="not_certified"'
    [ "$(sha256sum "$ATTACHMENT_CONFIG" "$ATTACHMENT_FIXTURE")" = "$before" ]
    [ ! -e "$IGOR_DATA_DIR/config/config.db" ]
}

@test "old session cannot use disabled provider and metadata remains meaningful" {
    _initialize
    proposal="$(_proposal)"
    _invoke_metadata core.deployments.adopt "$proposal" >/dev/null
    before="$(sha256sum "$IGOR_DATA_DIR/deployments/store.sqlite3" "$ATTACHMENT_CONFIG")"
    trace="$(cat "$ATTACHMENT_TRACE")"
    printf 'nextcloud_docker=disabled\n' > "$IGOR_DIR/config/modules.conf"
    run _igor_attachment_call discover '{}'
    [ "$status" -ne 0 ]
    [[ "$output" == *unavailable* ]]
    [ "$(cat "$ATTACHMENT_TRACE")" = "$trace" ]
    [ "$(sha256sum "$IGOR_DATA_DIR/deployments/store.sqlite3" "$ATTACHMENT_CONFIG")" = "$before" ]
    python3 "$REPO_DIR/core/lib/deployments.py" list | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; assert r["providers"][0]["inspection"]["availability"]=="disabled"; assert r["responsibilities"][0]["lifecycle"]=="active"; assert r["configuration"]["targets"][0]["availability"]=="unavailable"'
}

@test "changed native incarnation rejects frozen adoption before metadata binding" {
    _initialize
    proposal="$(_proposal)"
    python3 - "$ATTACHMENT_FIXTURE" <<'PY'
import json,sys
with open(sys.argv[1]) as f: row=json.load(f)
row['Created']='2026-01-01T00:00:00Z'
with open(sys.argv[1],'w') as f: json.dump(row,f)
PY
    run _invoke_metadata core.deployments.adopt "$proposal"
    [ "$status" -ne 0 ]
    [ "$(python3 "$REPO_DIR/core/lib/deployments.py" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["revision"])')" -eq 0 ]
}

teardown() { teardown_igor_tmpdir; }
