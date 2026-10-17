"""Increment D: authoritative frozen selections and READ mapping, without execution."""

import copy
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core/lib"))
from capability_runtime import CapabilityDescriptor, CapabilityError, CapabilityRegistry
from collection_runtime import Snapshots, context, prepare_inspection
from operational_history import OperationalHistory

sys.path.insert(0, str(ROOT / "core/ai"))
import tui
from test_ai_tui_collections import fixture as view_fixture


@pytest.fixture
def inspection(tmp_path, monkeypatch):
    monkeypatch.setenv("IGOR_DIR", str(tmp_path))
    monkeypatch.setenv("IGOR_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv("IGOR_RUNTIME_DIR", str(tmp_path / "runtime"))
    (tmp_path / "config").mkdir()
    (tmp_path / "config/modules.conf").write_text("system=enabled\n")
    declarations = json.loads((ROOT / "modules/system/contracts/host.json").read_text())["contributions"]
    registry = CapabilityRegistry()
    for ident in ("system.service.list", "system.service.status"):
        raw = copy.deepcopy(next(r for r in declarations if r.get("id") == ident))
        raw.update(owner="system", provider="system")
        registry.register(CapabilityDescriptor.from_dict(raw))
    now = [0.0]
    ctx = context(registry.prepare("system.service.list", {}, provider="system"), os.getpid(), "session-a")
    store = Snapshots(tmp_path / "runtime", clock=lambda: now[0])
    rows = [{"reference": {"scope_id": ctx["scope_id"], "object_id": "service:systemd:demo.service"},
             "unit": "demo.service", "active_state": "inactive", "sub_state": "dead"}]
    page = store.build(ctx, 50, lambda: iter(rows))
    selection = {"collection_id": "system.service.list", "provider": "system",
                 "snapshot_revision": page["page"]["snapshot_revision"], "reference": rows[0]["reference"]}
    def prepare(value=None, session="session-a", frozen=None):
        return prepare_inspection(registry, value or selection, os.getpid(), session, frozen=frozen, clock=lambda: now[0])
    return registry, store, selection, now, prepare, tmp_path


def test_snapshot_owned_inputs_and_frozen_target(inspection):
    _, _, selection, _, prepare, _ = inspection
    result = prepare()
    assert result["target"]["inputs"] == {"unit": "demo.service"}
    assert result["target"]["capability_version"] == 2 and result["target"]["safety"]["tier"] == "READ"
    assert result["reference"] == selection["reference"]
    assert prepare(frozen=result) == result


@pytest.mark.parametrize("change", ["scope", "object", "extra_reference", "args", "target", "revision", "collection", "provider", "session"])
def test_rejected_selections_cannot_produce_invocation(inspection, change):
    _, _, original, _, prepare, _ = inspection
    selection = copy.deepcopy(original)
    session = "session-a"
    if change == "scope": selection["reference"]["scope_id"] = "scope:" + "b" * 32
    elif change == "object": selection["reference"]["object_id"] = "service:systemd:other.service"
    elif change == "extra_reference": selection["reference"]["unit"] = "FORGED"
    elif change == "args": selection["inputs"] = {"unit": "FORGED"}
    elif change == "target": selection["capability_id"] = "system.service.restart"
    elif change == "revision": selection["snapshot_revision"] = "../private"
    elif change == "collection": selection["collection_id"] = "system.service.status"
    elif change == "provider": selection["provider"] = "other"
    else: session = "another-session"
    with pytest.raises((CapabilityError, ValueError)):
        prepare(selection, session=session)


@pytest.mark.parametrize("elapsed", [29.999, 30.0, 30.001])
def test_absolute_selection_expiry_without_renewal(inspection, elapsed):
    _, _, _, now, prepare, _ = inspection
    prepare()
    now[0] = elapsed
    if elapsed < 30:
        assert prepare()["target"]["inputs"]["unit"] == "demo.service"
    else:
        with pytest.raises(CapabilityError, match="^collection_expired$"):
            prepare()


@pytest.mark.parametrize("change", ["disabled", "replacement", "missing_binding", "change_target", "disabled_target", "target_version", "descriptor"])
def test_authority_changes_reject_frozen_inspection(inspection, change):
    registry, store, selection, _, prepare, root = inspection
    frozen = prepare()
    target = registry._selected("system.service.status", "system")
    collection = registry._selected("system.service.list", "system")
    if change == "disabled": (root / "config/modules.conf").write_text("system=disabled\n")
    elif change == "replacement": store.release(session="session-a")
    elif change == "missing_binding": del collection.collection["inspect"]
    elif change == "change_target": target.safety["tier"] = "CHANGE"
    elif change == "disabled_target": target.active = False
    elif change == "target_version": target.capability_version = 3
    else: target.description = "Different contract"
    with pytest.raises((CapabilityError, ValueError)):
        prepare(selection, frozen=frozen)


def test_explicit_inspection_provider_is_not_the_list_provider(inspection):
    registry, _, selection, _, prepare, root = inspection
    raw = registry._selected("system.service.status", "system").inspect()
    raw.pop("available", None)
    raw.update(provider="another", owner="another", handler="another__status")
    registry.register(CapabilityDescriptor.from_dict(raw))
    with pytest.raises(CapabilityError, match="^inspection_unavailable$"):
        prepare()
    explicit = dict(selection, inspection_provider="another")
    with pytest.raises(CapabilityError, match="^inspection_unavailable$"):
        prepare(explicit)
    (root / "config/modules.conf").write_text("system=enabled\nanother=enabled\n")
    assert prepare(explicit)["target"]["provider"] == "another"


def detail_event(view, registry, sequence=1):
    target = registry._selected("system.service.status", "system").inspect()
    return {"event_type": "action_result", "sequence": sequence, "view_request_id": view.request_id,
            "inspection": {"descriptor": target, "reference": view.detail_reference,
                           "snapshot_revision": view.revision, "freshness": view.freshness},
            "result": {"operation_id": "op-" + "b" * 32, "capability_id": target["id"],
                       "capability_version": 2, "owner": "system", "provider": "system", "outcome": "success",
                       "execution_status": "succeeded", "verification_status": "not_applicable", "output_status": "valid",
                       "result": {"unit": "demo0.service", "state": "active", "source": "platform.service_query"}}}


def test_ui_transmits_only_opaque_selection_and_back_keeps_page(inspection):
    registry, _, _, _, _, _ = inspection
    entry, result = view_fixture()
    view = tui.CollectionView(entry)
    view.accept(result)
    original = copy.deepcopy(view.pages)
    command = view.inspection_request()
    request = json.loads(command.split(" --inspect ", 1)[1])
    assert set(request) == {"collection_id", "provider", "snapshot_revision", "reference"}
    assert "unit" not in request and "inputs" not in request
    state = tui.EventState(collection=view, operator_snapshot={"entries": [entry]})
    event = detail_event(view, registry)
    assert tui.apply_event(state, event) and view.detail_state == "ready"
    assert view.detail_result["state"] == "active" and view.pages == original
    view.close_detail()
    assert view.pages == original and view.state == "ready"
    assert tui.apply_event(state, dict(event, sequence=2)) and view.detail_state == ""


@pytest.mark.parametrize("change", ["reference", "revision", "target", "tier", "output", "version"])
def test_bad_detail_projection_never_displays_rejected_values(inspection, change):
    registry, _, _, _, _, _ = inspection
    entry, result = view_fixture()
    view = tui.CollectionView(entry)
    view.accept(result)
    view.inspection_request()
    event = copy.deepcopy(detail_event(view, registry))
    if change == "reference": event["inspection"]["reference"]["object_id"] = "service:systemd:other.service"
    elif change == "revision": event["inspection"]["snapshot_revision"] = "other"
    elif change == "target": event["inspection"]["descriptor"]["id"] = "system.service.restart"
    elif change == "tier": event["inspection"]["descriptor"]["safety"]["tier"] = "CHANGE"
    elif change == "output": event["result"]["result"]["unapproved"] = "REJECTED_SENTINEL"
    else: event["result"]["capability_version"] = 3
    view.accept_detail(event)
    assert view.detail_state == "unavailable" and view.detail_result is None


def test_key_repeat_late_details_and_snapshot_expiry(inspection, monkeypatch):
    registry, _, _, _, _, _ = inspection
    entry, result = view_fixture()
    view = tui.CollectionView(entry)
    view.accept(result)
    state = tui.EventState(collection=view, backend_ready=True)
    sent = []
    monkeypatch.setattr(tui, "_send", lambda _, text: sent.append(text))
    from test_ai_tui_collections import Screen
    for _ in range(5): tui._collection_key(10, Screen(), 1, state)
    assert len(sent) == 1 and view.detail_state == "loading"
    event = copy.deepcopy(detail_event(view, registry))
    tui._collection_key(27, Screen(), 1, state)
    assert view.detail_state == ""
    assert tui.apply_event(state, event) and view.detail_state == ""
    state.backend_ready = True
    tui._collection_key(10, Screen(), 1, state)
    old = copy.deepcopy(detail_event(view, registry, 2))
    view.expires = 0
    assert view.expire() and view.state == "expired"
    assert tui.apply_event(state, old) and view.detail_state == "ready"
    view.close_detail()
    assert view.selected_reference() is None and view.inspection_request() is None


@pytest.mark.parametrize("rejection", ["expired", "cross_session", "changed_target"])
def test_canonical_execution_fence_never_reaches_handler(tmp_path, rejection):
    (tmp_path / "config").mkdir()
    (tmp_path / "config/modules.conf").write_text("system=enabled\n")
    builder = tmp_path / "build.py"
    builder.write_text(r'''import json,os,sys,hashlib
from pathlib import Path
sys.path.insert(0,sys.argv[1]+"/core/lib")
from capability_runtime import _registry_from_records
from collection_runtime import Snapshots,context,prepare_inspection,encoded
root=Path(os.environ["IGOR_DIR"])
all_records=json.loads(Path(sys.argv[1]+"/modules/system/contracts/host.json").read_text())["contributions"]
records=[dict(r,owner="system",provider="system") for r in all_records if r["id"] in {"system.service.list","system.service.status"}]
registry=_registry_from_records(records)
ctx=context(registry.prepare("system.service.list",{},provider="system"),int(sys.argv[2]),sys.argv[3])
store=Snapshots(root/"runtime")
row={"reference":{"scope_id":ctx["scope_id"],"object_id":"service:systemd:demo.service"},"unit":"demo.service","active_state":"inactive","sub_state":"dead"}
page=store.build(ctx,50,lambda:iter([row]))
selection={"collection_id":"system.service.list","provider":"system","snapshot_revision":page["page"]["snapshot_revision"],"reference":row["reference"]}
guard=prepare_inspection(registry,selection,int(sys.argv[2]),sys.argv[3])
proposal=dict(guard["target"],precondition_status="satisfied")
proposal.pop("digest")
proposal["digest"]=hashlib.sha256(encoded(proposal)).hexdigest()
for name,value in [("guard",guard),("proposal",proposal),("records",records),("collection",records[0])]:
    path=root/name;path.write_bytes(encoded(value));path.chmod(0o600)
if sys.argv[4]=="expired":store.release(session=sys.argv[3])
if sys.argv[4]=="changed_target":
    target=next(r for r in records if r["id"]=="system.service.status")
    target["description"]="changed contract"
    (root/"records").write_bytes(encoded(records))
''')
    script = r'''source "$1/core/lib/module_loader.sh"
source "$1/core/lib/capability.sh"
"$IGOR_PYTHON" "$IGOR_DIR/build.py" "$1" "$IGOR_CAPABILITY_RESULT_OWNER" "$IGOR_CAPABILITY_RESULT_FILE" "$2" || exit 10
_IGOR_CONTRIBUTIONS[capability:system.service.list]="$(cat "$IGOR_DIR/collection")"
igor_capability_list() { cat "$IGOR_DIR/records"; }
igor_capability_prepare() { cat "$IGOR_DIR/proposal"; }
_igor_capability_invoke_handler() { touch "$IGOR_DIR/HANDLER_REACHED"; return 1; }
proposal="$(cat "$IGOR_DIR/proposal")"
IGOR_CAPABILITY_APPROVED_DIGEST="$(_igor_capability_field "$proposal" digest)"
IGOR_CAPABILITY_APPROVAL_STATUS=approved
IGOR_COLLECTION_INSPECTION_FILE="$IGOR_DIR/guard"
if [ "$2" = cross_session ]; then IGOR_CAPABILITY_RESULT_FILE="$IGOR_DIR/different-session"; fi
igor_capability_execute "$proposal"
'''
    env = dict(os.environ, IGOR_DIR=str(tmp_path), IGOR_DATA_DIR=str(tmp_path / "data"),
               IGOR_RUNTIME_DIR=str(tmp_path / "runtime"), IGOR_PYTHON=sys.executable, IGOR_DISTRO_FAMILY="debian")
    result = subprocess.run(["bash", "-c", script, "_", str(ROOT), rejection], env=env,
                            capture_output=True, text=True, check=False, timeout=20)
    assert result.returncode == 0, result.stderr
    value = json.loads(result.stdout)
    assert value["execution_status"] == "not_executed" and value["outcome"] == "precondition_failed"
    assert value["verification_evidence"][0]["reason"] == {
        "expired": "collection_expired", "cross_session": "invalid_collection_selection",
        "changed_target": "inspection_unavailable"}[rejection]
    assert not (tmp_path / "HANDLER_REACHED").exists()


def test_dead_backend_pending_context_cleanup_and_guide_back(inspection):
    _, store, _, _, prepare, root = inspection
    record = prepare()
    record["session_owner"]["pid"] = 2147483647
    path = root / "runtime/.collection-inspection.orphan"
    path.write_text(json.dumps(record))
    path.chmod(0o600)
    store.inspect()
    assert not path.exists()
    entry, result = view_fixture()
    view = tui.CollectionView(entry)
    view.accept(result)
    view.inspection_request()
    state = tui.EventState(collection=view, pending_action={"classification": "READ", "operation_id": "pending"})
    from test_ai_tui_collections import Screen
    assert tui._collection_key(27, Screen(), 1, state)
    assert not view.detail_state and state.pending_action["operation_id"] == "pending"


@pytest.mark.parametrize("decision", ["run", "skip", "explain_skip", "policy_revoke", "owner_disable",
                                      "forged_reference", "policy_initial"])
def test_inspection_guide_policy_and_canonical_handler_boundary(tmp_path, decision):
    """Real Guide prompt and dispatcher; only observations/explanation are mocked."""
    root = tmp_path / "installation"
    (root / "modules").mkdir(parents=True)
    shutil.copytree(ROOT / "modules/system", root / "modules/system")
    (root / "core").symlink_to(ROOT / "core", target_is_directory=True)
    (root / "config").mkdir()
    (root / "config/modules.conf").write_text("system=enabled\n")
    (root / "data/runtime").mkdir(parents=True, mode=0o700)
    (root / "bin").mkdir()
    adapter = root / "bin/systemctl"
    adapter.write_text('#!/bin/sh\ncase "$1" in\nshow) printf "loaded\\n";;\nis-active) printf "active\\n";;\n*) exit 2;;\nesac\n')
    adapter.chmod(0o700)
    builder = root / "selection.py"
    builder.write_text(r'''import json,os,sys
from pathlib import Path
sys.path.insert(0,sys.argv[1]+"/core/lib")
from capability_runtime import _registry_from_records
from collection_runtime import Snapshots,context,encoded
registry=_registry_from_records(json.load(sys.stdin))
ctx=context(registry.prepare("system.service.list",{},provider="system",platform_family="debian"),int(sys.argv[2]),sys.argv[3])
row={"reference":{"scope_id":ctx["scope_id"],"object_id":"service:systemd:demo.service"},"unit":"demo.service","active_state":"inactive","sub_state":"dead"}
page=Snapshots(Path(os.environ["IGOR_RUNTIME_DIR"])).build(ctx,50,lambda:iter([row]))
selection={"collection_id":"system.service.list","provider":"system","snapshot_revision":page["page"]["snapshot_revision"],"reference":row["reference"]}
if sys.argv[4]=="forged_reference":selection["reference"]["object_id"]="service:systemd:FORGED_SENTINEL.service"
path=Path(os.environ["IGOR_DIR"])/"selection.json";path.write_bytes(encoded(selection));path.chmod(0o600)
''')
    script = r'''source "$1/core/lib/module_loader.sh"
_ml_log() { :; }
igor_load_all_modules >/dev/null || exit 10
source "$1/core/ai/core.sh"
source "$1/core/ai/control.sh"
igor_capability_list $'system.service.list\nsystem.service.status' | "$IGOR_PYTHON" "$IGOR_DIR/selection.py" "$1" "$IGOR_CAPABILITY_RESULT_OWNER" "$IGOR_CAPABILITY_RESULT_FILE" "$2" || exit 11
eval "$(declare -f _igor_capability_invoke_handler | sed '1s/_igor_capability_invoke_handler/_test_original_handler/')"
_igor_capability_invoke_handler() {
    printf 'handler\n' >> "$IGOR_DIR/handler-calls"
    _test_original_handler "$@"
}
eval "$(declare -f _ai_approval_prompt | sed '1s/_ai_approval_prompt/_test_original_prompt/')"
_ai_approval_prompt() {
    [ ! -e "$IGOR_DIR/handler-calls" ] || return 99
    printf '%s\n' "$1" >> "$IGOR_DIR/pending-records"
    _test_original_prompt "$@"
}
_ai_explain_pending_approval() {
    [ ! -e "$IGOR_DIR/handler-calls" ] || return 99
    printf '%s\n' "$1" >> "$IGOR_DIR/explain-records"
    AI_EXPLANATION_CACHE_TEXT='Fixture explanation: no execution authority.'
    case "$GUIDE_DECISION" in
        policy_revoke) IGOR_AI_ALLOWED_TOOLS=none ;;
        owner_disable) printf 'system=disabled\n' > "$IGOR_DIR/config/modules.conf" ;;
    esac
}
ai_mode=guide
[ "$GUIDE_DECISION" != policy_initial ] || IGOR_AI_ALLOWED_TOOLS=none
_ai_operator_invoke "--view=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --inspect $(cat "$IGOR_DIR/selection.json")"
rc=$?
printf '%s\n' "$rc" > "$IGOR_DIR/transport-status"
'''
    answers = {"run": "r\n", "skip": "s\n", "explain_skip": "e\ns\n",
               "policy_revoke": "e\nr\n", "owner_disable": "e\nr\n"}
    stream = root / "data/runtime/events"
    env = dict(os.environ, IGOR_DIR=str(root), IGOR_DATA_DIR=str(root / "data"),
               IGOR_RUNTIME_DIR=str(root / "data/runtime"), IGOR_PYTHON=sys.executable,
               IGOR_DISTRO_ID="debian", IGOR_DISTRO_FAMILY="debian", IGOR_AI_MODE="guide",
               IGOR_AI_EVENT_STREAM=str(stream), GUIDE_DECISION=decision,
               IGOR_AI_ENABLED="true", IGOR_AI_ALLOWED_TOOLS="all", PATH=str(root / "bin") + ":" + os.environ["PATH"])
    completed = subprocess.run(["bash", "-c", script, "_", str(ROOT), decision], env=env,
                               input=answers.get(decision, "r\n"), capture_output=True, text=True,
                               cwd=tmp_path, check=False, timeout=60)
    assert completed.returncode == 0, completed.stderr
    events = [json.loads(line) for line in stream.read_text().splitlines()]
    assert all(len(json.dumps(event, ensure_ascii=False, separators=(",", ":")).encode()) <= 98304 for event in events)
    assert not list((root / "data/runtime").glob(".collection-inspection.*"))
    calls = root / "handler-calls"
    if decision in {"forged_reference", "policy_initial"}:
        assert not calls.exists() and not (root / "pending-records").exists()
        assert not any(e["event_type"] == "approval_waiting" for e in events)
        assert not any(e.get("result", {}).get("execution_status") == "succeeded" for e in events)
        assert "FORGED_SENTINEL" not in completed.stdout + completed.stderr + json.dumps(events)
        return
    pending = [json.loads(line) for line in (root / "pending-records").read_text().splitlines()]
    assert len(pending) == 1 and pending[0]["tier"] == "READ"
    assert pending[0]["normalized_args"]["inputs"] == {"unit": "demo.service"}
    waiting = [e for e in events if e["event_type"] == "approval_waiting"]
    assert len(waiting) == 1 and waiting[0]["operation_id"] == pending[0]["operation_id"]
    if decision in {"explain_skip", "policy_revoke", "owner_disable"}:
        explained = [json.loads(line) for line in (root / "explain-records").read_text().splitlines()]
        assert explained == pending
    results = [e for e in events if e["event_type"] == "action_result" and e.get("inspection")]
    assert len(results) == 1
    result = results[0]["result"]
    # Approval events retain the session action ID; History owns the durable op ID.
    assert results[0]["view_request_id"] == "a" * 32
    episode = OperationalHistory(root / "data").inspect(result["operation_id"])
    assert episode["operation_id"] == result["operation_id"]
    assert episode["capability"] == {"id": "system.service.status", "version": 2}
    assert episode["affected_objects"] == [results[0]["inspection"]["reference"]]
    assert episode["provenance"]["interface"] == "operator_surface"
    assert episode["approval"]["requirement"] == "guide_confirm" and episode["lifecycle"] == "terminal"
    if decision == "run":
        assert calls.read_text().splitlines() == ["handler"]
        assert result["execution_status"] == "succeeded" and result["output_status"] == "valid"
        assert result["result"] == {"unit": "demo.service", "state": "active", "source": "platform.service_query"}
        assert episode["approval"]["result"] == "approved"
    else:
        assert not calls.exists() and result["execution_status"] == "not_executed"
        assert result["outcome"] == {"skip": "approval_denied", "explain_skip": "approval_denied",
                                     "policy_revoke": "approval_invalid", "owner_disable": "precondition_failed"}[decision]
        if decision == "owner_disable":
            assert result["verification_evidence"][0]["reason"] == "collection_expired"
