"""Portable Igor Knowledge Artifacts using an OKF v0.2-compatible bundle profile.

This is an interchange boundary, not a memory or authority store. Export reads an
accepted Local Learning artifact and writes one Markdown concept plus root
index.md. Import validates/normalizes one OKF concept and returns an untrusted
reference candidate without persisting or activating it.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import re
import shutil
import stat
import sys
from pathlib import Path
from typing import Any

from local_learning import LearningError, LocalLearningService, validate_learning

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ai"))
from privacy import scrub_text

VERSION = 1
OKF_VERSION = "0.2"
CONTRACT = "igor.knowledge_artifact"
IMPORT_CONTRACT = "igor.knowledge_artifact.import_candidate"
STATUS_CONTRACT = "igor.knowledge_artifact.status"
MAX_FILE_BYTES = 262144
MAX_BODY_BYTES = 131072
MAX_FRONTMATTER_FIELDS = 64
MAX_DEPTH = 16
MAX_ITEMS = 512
_ARTIFACT = re.compile(r"ka-[0-9a-f]{64}")
_IMPORT = re.compile(r"ki-[0-9a-f]{64}")
_SAFE_KEY = re.compile(r"[A-Za-z][A-Za-z0-9_.-]{0,127}")
_SENSITIVE = re.compile(r"(?:password|passwd|secret|token|api[_-]?key|private[_-]?key)", re.IGNORECASE)
_TYPES = {
    "recurring_outcome",
    "investigation_finding",
    "typed_investigation_finding",
    "cross_incident_pattern",
    "reference_procedure",
}


class KnowledgeArtifactError(ValueError):
    """Invalid, unsafe, unsupported, or non-portable knowledge material."""


def _check(condition: bool, message: str = "knowledge artifact contract validation failed") -> None:
    if not condition:
        raise KnowledgeArtifactError(message)


def _compact(value: Any) -> str:
    try:
        return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"), allow_nan=False)
    except (TypeError, ValueError, RecursionError) as exc:
        raise KnowledgeArtifactError("invalid knowledge artifact JSON") from exc


def _digest(value: Any) -> str:
    return hashlib.sha256(_compact(value).encode("utf-8")).hexdigest()


def _safe_text(value: Any, limit: int = 8192, *, empty: bool = False) -> str:
    _check(type(value) is str and len(value) <= limit and (empty or bool(value)), "invalid knowledge text")
    _check("\x00" not in value and not re.search(r"[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]", value),
           "unsafe knowledge text")
    _check(scrub_text(value) == value, "secret-bearing knowledge text")
    return value


def _safe_value(value: Any, *, depth: int = 0) -> Any:
    _check(depth <= MAX_DEPTH, "knowledge structure too deep")
    if type(value) is dict:
        _check(len(value) <= MAX_ITEMS, "knowledge mapping too large")
        result = {}
        for key, item in value.items():
            _check(type(key) is str and _SAFE_KEY.fullmatch(key), "invalid knowledge key")
            _check(not _SENSITIVE.search(key), "sensitive knowledge key")
            result[key] = _safe_value(item, depth=depth + 1)
        return result
    if type(value) is list:
        _check(len(value) <= MAX_ITEMS, "knowledge list too large")
        return [_safe_value(item, depth=depth + 1) for item in value]
    if type(value) is str:
        return _safe_text(value, MAX_BODY_BYTES, empty=True)
    _check(value is None or type(value) in {bool, int, float}, "unsupported knowledge value")
    if type(value) is float:
        _check(math.isfinite(value), "nonfinite knowledge number")
    return value


def _slug(value: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip()).strip("-").lower()
    return slug[:80] or "operator"


def _title(learning_type: str) -> str:
    return {
        "recurring_outcome": "Recurring operational outcome",
        "investigation_finding": "Reviewed investigation finding",
        "typed_investigation_finding": "Reviewed typed investigation finding",
        "cross_incident_pattern": "Cross-incident symptom/cause pattern",
        "reference_procedure": "Evidence-backed reference procedure",
    }[learning_type]


def _portable_artifact(row: dict) -> dict:
    try:
        row = validate_learning(row)
    except LearningError as exc:
        raise KnowledgeArtifactError("invalid Local Learning source") from exc
    _check(row["status"] == "accepted", "only accepted Local Learning can be exported")
    candidate = row["candidate"]
    learning_type = candidate["learning_type"]
    _check(learning_type in _TYPES, "unsupported learning type for portability")
    content = {
        "statement": candidate["statement"],
        "uncertainty": candidate["uncertainty"],
    }
    for key in ("pattern", "procedure"):
        if key in candidate:
            content[key] = candidate[key]
    if candidate["outcome"] is not None:
        content["outcome"] = candidate["outcome"]
    if candidate["capability"] is not None:
        content["capability"] = candidate["capability"]
    if candidate["provider"] is not None:
        content["provider"] = candidate["provider"]
    evidence = [{"kind": ref["kind"], "digest": ref["digest"]} for ref in candidate["evidence"]]
    semantic = {
        "knowledge_type": learning_type,
        "content": content,
        "applicability": {
            "owners": candidate["applicability_owners"],
            "compatibility": candidate["compatibility"],
            "source_objects": candidate["related_objects"],
        },
        "candidate_revision": candidate["candidate_revision"],
    }
    value = {
        "contract": CONTRACT,
        "version": VERSION,
        "authority": "reference_only",
        "artifact_id": "ka-" + _digest(semantic),
        "knowledge_type": learning_type,
        "origin": "learned_local",
        "title": _title(learning_type),
        "description": candidate["statement"],
        "content": content,
        "applicability": semantic["applicability"],
        "provenance": {
            "source_scope": candidate["scope_id"],
            "source_learning_id": row["learning_id"],
            "candidate_id": candidate["candidate_id"],
            "candidate_revision": candidate["candidate_revision"],
            "derivation": candidate["provenance"],
            "evidence": evidence,
        },
        "review": {
            "at": row["review"]["at"],
            "actor": row["review"]["actor"],
            "interface": row["review"]["interface"],
            "result": row["review"]["result"],
        },
        "generated_at": row["timestamps"]["updated_at"],
    }
    return validate_artifact(value)


def validate_artifact(value: Any) -> dict:
    value = _safe_value(value)
    _check(type(value) is dict and set(value) == {
        "contract", "version", "authority", "artifact_id", "knowledge_type", "origin",
        "title", "description", "content", "applicability", "provenance", "review", "generated_at",
    })
    _check(value["contract"] == CONTRACT and value["version"] == VERSION)
    _check(value["authority"] == "reference_only" and value["origin"] in {"learned_local", "imported"})
    _check(type(value["artifact_id"]) is str and _ARTIFACT.fullmatch(value["artifact_id"]))
    _check(value["knowledge_type"] in _TYPES)
    _safe_text(value["title"], 160)
    _safe_text(value["description"], 4096)
    _safe_text(value["generated_at"], 64)
    applicability = value["applicability"]
    _check(type(applicability) is dict and set(applicability) == {"owners", "compatibility", "source_objects"})
    _check(type(applicability["owners"]) is list and bool(applicability["owners"]))
    _check(type(applicability["compatibility"]) is list and bool(applicability["compatibility"]))
    _check(type(applicability["source_objects"]) is list and bool(applicability["source_objects"]))
    provenance = value["provenance"]
    _check(type(provenance) is dict and {
        "source_scope", "source_learning_id", "candidate_id", "candidate_revision", "derivation", "evidence"
    } <= provenance.keys())
    review = value["review"]
    _check(type(review) is dict and set(review) == {"at", "actor", "interface", "result"})
    _check(review["result"] == "accepted")
    semantic = {
        "knowledge_type": value["knowledge_type"],
        "content": value["content"],
        "applicability": value["applicability"],
        "candidate_revision": provenance["candidate_revision"],
    }
    _check(value["artifact_id"] == "ka-" + _digest(semantic), "knowledge artifact identity mismatch")
    return value


def _source_entries(artifact: dict) -> list[dict]:
    entries = []
    for index, ref in enumerate(artifact["provenance"]["evidence"], 1):
        entries.append({
            "id": f"evidence-{index}",
            "resource": f"urn:igor:evidence:{ref['kind']}:{ref['digest']}",
            "title": f"Igor {ref['kind']} evidence",
        })
    return entries


def _frontmatter(front: dict) -> str:
    lines = ["---"]
    for key, value in front.items():
        _check(_SAFE_KEY.fullmatch(key) is not None)
        lines.append(f"{key}: {_compact(value)}")
    lines.append("---")
    return "\n".join(lines) + "\n"


def _body(artifact: dict) -> str:
    content = artifact["content"]
    lines = [
        f"# {artifact['title']}",
        "",
        "## Statement",
        "",
        content["statement"],
        "",
    ]
    if "pattern" in content:
        lines += ["## Pattern", "", "    " + _compact(content["pattern"]), ""]
    if "procedure" in content:
        lines += ["## Procedure", "", "    " + _compact(content["procedure"]), ""]
    if content["uncertainty"]:
        lines += ["## Uncertainty", ""]
        lines += [f"- {item}" for item in content["uncertainty"]]
        lines.append("")
    lines += [
        "## Authority",
        "",
        "Reference knowledge only. This artifact does not grant execution, approval, privilege, automation, desired-state, remediation, or capability authority.",
        "",
    ]
    body = "\n".join(lines)
    _safe_text(body, MAX_BODY_BYTES)
    return body


def _render_concept(artifact: dict) -> str:
    actor = "human:" + _slug(artifact["review"]["actor"])
    front = {
        "type": "Igor Knowledge Artifact",
        "title": artifact["title"],
        "description": artifact["description"],
        "resource": "urn:igor:knowledge:" + artifact["artifact_id"],
        "tags": ["igor", "reference-knowledge", artifact["knowledge_type"].replace("_", "-")],
        "status": "stable",
        "generated": {"by": "process:igor", "at": artifact["generated_at"]},
        "verified": {"by": actor, "at": artifact["review"]["at"]},
        "sources": _source_entries(artifact),
        "igor_artifact": artifact,
    }
    return _frontmatter(front) + _body(artifact)


def _render_index(filename: str, artifact: dict) -> str:
    return (
        _frontmatter({"okf_version": OKF_VERSION})
        + "# Igor Knowledge Artifact Bundle\n\n"
        + f"* [{artifact['title']}]({filename}) - {artifact['description']}\n"
    )


def _read_regular(path: Path) -> str:
    _check(path.exists() and path.is_file() and not path.is_symlink(), "knowledge bundle file unavailable")
    info = path.stat()
    _check(stat.S_ISREG(info.st_mode) and info.st_size <= MAX_FILE_BYTES, "knowledge bundle file invalid")
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise KnowledgeArtifactError("knowledge bundle file unreadable") from exc


def _parse_scalar(raw: str) -> Any:
    raw = raw.strip()
    _check(raw != "", "empty frontmatter value")
    if raw[0] in '"[{' or raw in {"true", "false", "null"} or re.fullmatch(r"-?\d+(?:\.\d+)?", raw):
        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            raise KnowledgeArtifactError("unsupported frontmatter value") from exc
    _check(not any(token in raw for token in ("&", "*", "!", "|", ">", "{", "}", "[", "]")),
           "unsupported YAML feature")
    return raw


def _parse_document(raw: str, *, index: bool = False) -> tuple[dict, str]:
    _check(len(raw.encode("utf-8")) <= MAX_FILE_BYTES, "knowledge document too large")
    lines = raw.splitlines()
    _check(lines and lines[0] == "---", "OKF document requires frontmatter")
    try:
        close = lines.index("---", 1)
    except ValueError as exc:
        raise KnowledgeArtifactError("unterminated OKF frontmatter") from exc
    front = {}
    for line in lines[1:close]:
        if not line.strip():
            continue
        _check(line == line.lstrip(), "multiline/indented YAML is outside Igor OKF profile")
        key, sep, value = line.partition(":")
        _check(sep == ":" and _SAFE_KEY.fullmatch(key) and key not in front, "invalid OKF frontmatter")
        _check(value.strip(), "multiline/indented YAML is outside Igor OKF profile")
        front[key] = _parse_scalar(value)
    _check(len(front) <= MAX_FRONTMATTER_FIELDS, "too many OKF frontmatter fields")
    tail = lines[close + 1:]
    body = "\n".join(tail).strip() + ("\n" if tail else "")
    _safe_value(front)
    _safe_text(body, MAX_BODY_BYTES, empty=True)
    if index:
        _check(set(front) <= {"okf_version"}, "unsupported root index frontmatter")
    else:
        _check(type(front.get("type")) is str and bool(front["type"]), "OKF concept requires type")
    return front, body


def _validate_standard_front(front: dict) -> dict:
    result = {
        "type": front["type"],
        "title": front.get("title"),
        "description": front.get("description"),
        "resource": front.get("resource"),
        "tags": front.get("tags", []),
        "status": front.get("status", "stable"),
    }
    _safe_text(result["type"], 160)
    for key in ("title", "description", "resource"):
        if result[key] is not None:
            _safe_text(result[key], 4096)
    _check(type(result["tags"]) is list and all(type(tag) is str for tag in result["tags"]),
           "invalid OKF tags")
    _check(result["status"] in {"draft", "stable", "deprecated"}, "invalid OKF lifecycle status")
    for key in ("generated", "verified", "sources", "stale_after"):
        if key in front:
            result[key] = _safe_value(front[key])
    return result


def _bundle_path(value: Any) -> Path:
    _check(type(value) is str and bool(value) and len(value) <= 4096, "invalid bundle directory")
    path = Path(value).expanduser().absolute()
    for component in (path, *path.parents):
        if component.exists():
            _check(not component.is_symlink(), "bundle path contains a symlink")
    return path


class KnowledgeArtifactService:
    """Stateless portability adapter. Import never persists or activates knowledge."""

    def __init__(self, data_dir: Path):
        self._learning = LocalLearningService(Path(data_dir))

    @staticmethod
    def status() -> dict:
        return {
            "contract": STATUS_CONTRACT,
            "version": VERSION,
            "authority": "reference_only",
            "persistence": "none",
            "okf_version": OKF_VERSION,
            "profile": "single-concept-json-compatible-frontmatter",
            "import_effect": "validate_only",
        }

    def export(self, learning_id: str, directory: str) -> dict:
        _safe_text(learning_id, 160)
        try:
            artifact = _portable_artifact(self._learning.inspect(learning_id))
        except LearningError as exc:
            raise KnowledgeArtifactError("Local Learning source unavailable") from exc
        target = _bundle_path(directory)
        _check(not target.exists(), "export directory already exists")
        parent = target.parent
        _check(parent.exists() and parent.is_dir() and not parent.is_symlink(), "export parent unavailable")
        filename = artifact["artifact_id"] + ".md"
        try:
            target.mkdir(mode=0o700)
            (target / "index.md").write_text(_render_index(filename, artifact), encoding="utf-8")
            (target / filename).write_text(_render_concept(artifact), encoding="utf-8")
            os.chmod(target / "index.md", 0o600)
            os.chmod(target / filename, 0o600)
        except OSError as exc:
            shutil.rmtree(target, ignore_errors=True)
            raise KnowledgeArtifactError("knowledge bundle export failed") from exc
        return {
            "contract": "igor.knowledge_artifact.export",
            "version": VERSION,
            "authority": "reference_only",
            "okf_version": OKF_VERSION,
            "artifact_id": artifact["artifact_id"],
            "directory": str(target),
            "files": ["index.md", filename],
        }

    def import_bundle(self, directory: str) -> dict:
        root = _bundle_path(directory)
        _check(root.exists() and root.is_dir() and not root.is_symlink(), "knowledge bundle unavailable")
        index_front, _ = _parse_document(_read_regular(root / "index.md"), index=True)
        declared = index_front.get("okf_version")
        _check(declared in {None, OKF_VERSION}, "unsupported OKF version")
        concepts = sorted(
            path for path in root.iterdir()
            if path.name not in {"index.md", "log.md"} and path.suffix == ".md"
        )
        _check(len(concepts) == 1, "Igor OKF profile requires exactly one concept")
        _check(not any(path.is_symlink() for path in concepts), "symlinked concepts are not allowed")
        front, body = _parse_document(_read_regular(concepts[0]))
        concept = _validate_standard_front(front)
        extension = None
        if "igor_artifact" in front:
            extension = validate_artifact(front["igor_artifact"])
        normalized = {
            "contract": IMPORT_CONTRACT,
            "version": VERSION,
            "authority": "reference_only",
            "trust": "untrusted_import",
            "persistence": "none",
            "source_format": "okf",
            "okf_version": declared or "unspecified",
            "concept": concept,
            "content": {"markdown": body},
            "provenance": {
                "generated": front.get("generated"),
                "verified": front.get("verified"),
                "sources": front.get("sources", []),
            },
            "igor_artifact": extension,
        }
        normalized["import_id"] = "ki-" + _digest(normalized)
        _check(_IMPORT.fullmatch(normalized["import_id"]) is not None)
        return normalized


def _data_dir() -> Path:
    return Path(os.environ.get(
        "IGOR_DATA_DIR",
        os.environ.get("IGOR_RUNTIME_DIR", Path.home() / ".local/share/igor"),
    ))


def _request() -> dict:
    raw = sys.stdin.read(MAX_FILE_BYTES + 1)
    _check(len(raw.encode("utf-8")) <= MAX_FILE_BYTES, "knowledge request too large")
    try:
        value = json.loads(raw or "{}")
    except json.JSONDecodeError as exc:
        raise KnowledgeArtifactError("invalid knowledge request JSON") from exc
    _check(type(value) is dict, "knowledge request must be an object")
    return value


def main(argv: list[str]) -> int:
    action = argv[1] if len(argv) > 1 else "status"
    service = KnowledgeArtifactService(_data_dir())
    request = _request()
    if action == "status":
        _check(not request, "status takes no arguments")
        result = service.status()
    elif action == "export":
        _check(set(request) == {"learning_id", "directory"}, "export requires learning_id and directory")
        result = service.export(request["learning_id"], request["directory"])
    elif action == "import":
        _check(set(request) == {"directory"}, "import requires directory")
        result = service.import_bundle(request["directory"])
    else:
        raise KnowledgeArtifactError("unknown knowledge artifact action")
    print(_compact(result))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except KnowledgeArtifactError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(2) from exc
