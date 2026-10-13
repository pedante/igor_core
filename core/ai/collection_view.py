"""Disposable collection presentation; execution and cursor authority stay in Core."""

import copy
import json
import re
import time
import unicodedata
import uuid
from dataclasses import dataclass, field
from datetime import datetime

from capability_runtime import (
    CapabilityError,
    _validate_result,
    validate_output_schema,
    validate_outputs,
)


def cell_text(value, width=80, *, pad=False):
    """Terminal-safe, cell-width-bounded values; never used as invocation inputs."""
    if value is None:
        text = "-"
    elif isinstance(value, bool):
        text = "true" if value else "false"
    elif isinstance(value, (dict, list)):
        text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    else:
        text = str(value)
    result, used = [], 0
    for char in text:
        if unicodedata.category(char).startswith("C"):
            char = "?"
        if unicodedata.combining(char) and not result:
            char = "?"
        size = 0 if unicodedata.combining(char) else (2 if unicodedata.east_asian_width(char) in {"W", "F"} else 1)
        if used + size > max(0, width):
            break
        # Bound combining marks as well as terminal cells.
        if len(result) >= max(1, width * 2):
            break
        result.append(char)
        used += size
    return "".join(result) + (" " * max(0, width - used) if pad else "")


@dataclass
class CollectionView:
    entry: dict
    state: str = "loading"
    request_id: str = ""
    request_kind: str = "refresh"
    pages: list = field(default_factory=list)
    page_index: int = 0
    selection: int = 0
    scroll: int = 0
    query: str = ""
    filtering: bool = False
    limit: int = 50
    expires: float = 0
    revision: str = ""
    freshness: dict = field(default_factory=dict)
    operation_id: str = ""
    columns: list = field(default_factory=list)
    column_offset: int = 0
    notice: str = ""

    def __post_init__(self):
        if (not re.fullmatch(r"[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+", self.entry["target_id"]) or
                not re.fullmatch(r"[a-z][a-z0-9_-]*", self.entry["provider"])):
            raise CapabilityError("invalid collection target")
        schema = validate_output_schema(self.entry["outputs"], collection=self.entry["collection"])
        fields = schema["properties"]["rows"]["items"]["properties"]
        self.columns = copy.deepcopy(self.entry["collection"].get("columns") or
                                     [{"field": name, "label": name} for name in fields])

    def expire(self):
        if self.pages and time.monotonic() >= self.expires:
            self.fail("expired")
            return True
        return False

    def fail(self, state):
        self.state = state
        self.pages.clear()
        self.selection = self.scroll = self.page_index = 0
        self.request_id = ""

    def request(self, kind="refresh"):
        self.expire()
        inputs = {}
        if kind == "next":
            if self.state != "ready" or not self.pages[self.page_index][0]["page"]["has_more"]:
                return None
            inputs = {"limit": self.limit, "cursor": self.pages[self.page_index][0]["page"]["next_cursor"]}
        else:
            self.pages.clear()
            self.revision = ""
            self.freshness = {}
            self.page_index = self.selection = self.scroll = 0
        self.request_kind = kind
        self.request_id = uuid.uuid4().hex
        self.state = "loading"
        target = self.entry["target_id"] + "@" + self.entry["provider"]
        return "invoke --view=" + self.request_id + " " + target + " " + json.dumps(inputs, separators=(",", ":"))

    def accept(self, result):
        """Recheck presentation data with the canonical validator, not a UI schema."""
        try:
            _validate_result(result)
            if not re.fullmatch(r"op-[0-9a-f]{32}", result["operation_id"]):
                raise CapabilityError("invalid operation identity")
            if (result.get("capability_id") != self.entry["target_id"] or
                    result.get("provider") != self.entry["provider"] or
                    result.get("owner") != self.entry["owner"] or result.get("capability_version") != 3):
                raise CapabilityError("mismatched collection result")
            if result.get("output_status") != "valid" or result.get("outcome") != "success":
                reasons = {item.get("reason") for item in result.get("verification_evidence", []) if isinstance(item, dict)}
                self.fail("expired" if reasons & {"collection_expired", "invalid_collection_cursor"} else
                          "invalid" if result.get("output_status") == "invalid" else "unavailable")
                return
            scope = (self.pages[self.page_index][0]["rows"][0]["reference"]["scope_id"]
                     if self.request_kind == "next" and self.pages else None)
            page = validate_outputs(self.entry["outputs"], result["result"], collection=self.entry["collection"], scope_id=scope)
            revision = page["page"]["snapshot_revision"]
            if self.request_kind == "next" and (revision != self.revision or page["freshness"] != self.freshness):
                raise CapabilityError("mixed collection snapshots")
            if self.entry.get("availability") != "active":
                self.fail("unavailable")
                return
            if self.request_kind == "next":
                previous, start = self.pages[self.page_index]
                start += previous["page"]["returned_count"]
                if page["page"]["total_count"] != previous["page"]["total_count"] or start + len(page["rows"]) > page["page"]["total_count"]:
                    raise CapabilityError("inconsistent collection page")
                references = {json.dumps(row["reference"], sort_keys=True) for row in previous["rows"]}
                if any(json.dumps(row["reference"], sort_keys=True) in references for row in page["rows"]):
                    raise CapabilityError("repeated collection rows")
            else:
                start = 0
                if page["page"]["has_more"]:
                    self.limit = page["page"]["returned_count"]
            end = start + len(page["rows"])
            if ((not page["page"]["has_more"] and end != page["page"]["total_count"]) or
                    (page["page"]["has_more"] and len(page["rows"]) != self.limit)):
                raise CapabilityError("incomplete collection page")
            remaining = datetime.fromisoformat(page["freshness"]["expires_at"].replace("Z", "+00:00")).timestamp() - time.time()
            deadline = time.monotonic() + min(30, max(0, remaining))
            self.expires = min(self.expires, deadline) if self.pages else deadline
            self.pages = (self.pages + [(page, start)])[-2:]
            self.page_index = len(self.pages) - 1
            self.revision, self.freshness = revision, page["freshness"]
            self.operation_id = result["operation_id"]
            self.selection = self.scroll = 0
            self.request_id = ""
            self.state = "ready" if page["rows"] else "empty"
            self.expire()
        except (CapabilityError, KeyError, TypeError, ValueError, RecursionError):
            self.fail("invalid")

    def rows(self):
        if not self.pages:
            return []
        return [row for row in self.pages[self.page_index][0]["rows"] if self.query.casefold() in
                " ".join(cell_text(row.get(column["field"]), 256) for column in self.columns).casefold()]

    def selected_reference(self):
        self.expire()
        rows = self.rows()
        if self.state == "ready" and rows:
            return copy.deepcopy(rows[min(self.selection, len(rows) - 1)]["reference"])
        return None

    def move(self, delta):
        self.expire()
        if self.state == "ready":
            self.selection = max(0, min(max(0, len(self.rows()) - 1), self.selection + delta))

    def cached_page(self, delta):
        self.expire()
        index = self.page_index + delta
        if self.state == "ready" and 0 <= index < len(self.pages):
            self.page_index = index
            self.selection = self.scroll = 0
            return True
        return False

    def inspect(self):
        """Bounded UI state inspection, without exposing continuation tokens."""
        self.expire()
        return {"state": self.state, "capability_id": self.entry["target_id"],
                "provider": self.entry["provider"], "operation_id": self.operation_id,
                "snapshot_revision": self.revision, "retained_pages": len(self.pages),
                "freshness": copy.deepcopy(self.freshness),
                "page": ({k: v for k, v in self.pages[self.page_index][0]["page"].items() if k != "next_cursor"}
                         if self.pages else None), "selected_reference": self.selected_reference(),
                "page_local_filter": self.query, "request_pending": bool(self.request_id)}


def result_entry(snapshot, result):
    if not isinstance(snapshot, dict) or not isinstance(result, dict):
        return None
    matches = [entry for entry in snapshot.get("entries", []) if isinstance(entry, dict) and
               entry.get("kind") == "capability" and entry.get("target_id") == result.get("capability_id") and
               entry.get("provider") == result.get("provider") and "collection" in entry]
    return matches[0] if len(matches) == 1 else None


def view_request_id(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{32}", value) is not None
