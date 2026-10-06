"""Process-local Igor System Model and the Wave D observation validation boundary.

The public operations use records rather than a storage path. A new process starts
with an empty model; source adapters may replay validated intent.
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timedelta, timezone
from typing import Any

STATE_CLASSES = {"observed", "configured", "user_declared", "desired", "inferred"}
VALUE_TYPES = {"integer", "number", "boolean", "string"}
PROVENANCE_KINDS = {"observer", "configuration", "user_declaration", "installer", "inference"}


def now() -> datetime:
    return datetime.now(timezone.utc)


def stamp(value: datetime) -> str:
    return value.isoformat(timespec="seconds").replace("+00:00", "Z")


def key(object_id: str, prop: str, state_class: str) -> str:
    return json.dumps([object_id, prop, state_class], separators=(",", ":"))


def _typed(value: Any, value_type: str) -> bool:
    return {
        "integer": lambda: type(value) is int,
        "number": lambda: type(value) in (int, float),
        "boolean": lambda: type(value) is bool,
        "string": lambda: type(value) is str,
    }[value_type]()


def _identifier(value: Any) -> bool:
    return isinstance(value, str) and len(value) <= 160 and bool(re.fullmatch(r"[a-z][a-z0-9_-]*:[A-Za-z0-9_./:%+-]+", value))


def _observer_target(descriptor: dict[str, Any]) -> str:
    if descriptor.get("object_kind") == "host":
        return "host:local"
    kind, target = descriptor.get("object_kind"), descriptor.get("object_id")
    if kind in {"deployment", "resource"} and isinstance(target, str) and re.fullmatch(kind + r":[0-9a-f]{32}", target):
        return target
    raise ModelError("unsupported observer target")


def _object_matches_kind(object_id: Any, object_kind: Any) -> bool:
    if not _identifier(object_id) or not isinstance(object_kind, str):
        return False
    if object_kind == "host":
        return object_id == "host:local"
    if object_kind in {"deployment", "resource"}:
        return re.fullmatch(object_kind + r":[0-9a-f]{32}", object_id) is not None
    if object_kind in {"mount", "filesystem"}:
        return object_id.startswith(object_kind + ":/")
    if object_kind == "user":
        return re.fullmatch(r"user:uid:[0-9]+", object_id) is not None
    if object_kind == "group":
        return re.fullmatch(r"group:gid:[0-9]+", object_id) is not None
    return False


class ModelError(ValueError):
    pass


class SystemModel:
    def __init__(self, state: dict[str, Any] | None = None):
        state = state or {}
        self.facts = dict(state.get("facts", {}))
        self.failures = dict(state.get("failures", {}))
        self.responsibilities = list(state.get("responsibilities", []))
        self.attempts = dict(state.get("attempts", {}))
        self.health = dict(state.get("health", {}))

    def dump(self) -> dict[str, Any]:
        return {"facts": self.facts, "failures": self.failures,
                "responsibilities": self.responsibilities, "attempts": self.attempts,
                "health": self.health}

    def read(self, object_id: str, prop: str, state_class: str,
             *, active_owners: set[str] | None = None, at: datetime | None = None) -> dict[str, Any]:
        if state_class not in STATE_CLASSES:
            raise ModelError("unsupported state class")
        slot = key(object_id, prop, state_class)
        fact = self.facts.get(slot)
        failure = self.failures.get(slot)
        if fact is None:
            return {"object_id": object_id, "property": prop, "state_class": state_class,
                    "availability": "unknown" if failure else "not_observed",
                    "reason": failure.get("reason") if failure else None}
        record = dict(fact)
        expires = record.get("expires_at")
        expired = bool(expires and datetime.fromisoformat(expires.replace("Z", "+00:00")) <= (at or now()))
        inactive = active_owners is not None and record["owner"] not in active_owners
        record["availability"] = "inactive" if inactive else "stale" if failure or expired else "known"
        record["reason"] = "owner_inactive" if inactive else failure.get("reason") if failure else "expired" if expired else None
        if state_class == "inferred" and record["availability"] == "known":
            for input_key in record["provenance"]["inputs"]:
                source = self.facts.get(key(*input_key))
                if source is None:
                    record["availability"], record["reason"] = "unknown", "input_not_observed"
                    break
                source_expiry = source.get("expires_at")
                source_stale = bool(source_expiry and datetime.fromisoformat(source_expiry.replace("Z", "+00:00")) <= (at or now()))
                if key(*input_key) in self.failures or source_stale or (active_owners is not None and source["owner"] not in active_owners):
                    record["availability"], record["reason"] = "stale", "input_stale"
                    break
        return record

    def list_facts(self, *, object_id: str | None = None, prop: str | None = None,
                   state_class: str | None = None, active_owners: set[str] | None = None) -> list[dict[str, Any]]:
        result = []
        for fact in self.facts.values():
            if object_id and fact["object_id"] != object_id:
                continue
            if prop and fact["property"] != prop:
                continue
            if state_class and fact["state_class"] != state_class:
                continue
            result.append(self.read(fact["object_id"], fact["property"], fact["state_class"], active_owners=active_owners))
        return result

    def upsert_from_source(self, source_id: str, snapshot: dict[str, Any], *, at: datetime | None = None) -> None:
        """Atomically replace records projected from one named authority."""
        if not isinstance(source_id, str) or not source_id or len(source_id) > 160:
            raise ModelError("invalid source")
        if not isinstance(snapshot, dict) or set(snapshot) != {"facts", "responsibilities"}:
            raise ModelError("invalid source snapshot")
        new_facts: dict[str, dict[str, Any]] = {}
        new_responsibilities: list[dict[str, Any]] = []
        for item in snapshot["facts"]:
            if not isinstance(item, dict) or set(item) != {"object_id", "property", "state_class", "value", "value_type", "owner", "provenance"}:
                raise ModelError("invalid source fact")
            if not _identifier(item["object_id"]) or not isinstance(item["property"], str) or not re.fullmatch(r"[a-z][a-z0-9_.]*", item["property"]):
                raise ModelError("invalid fact key")
            if item["state_class"] not in STATE_CLASSES - {"observed"}:
                raise ModelError("source cannot publish observed state")
            if item["value_type"] not in VALUE_TYPES or not _typed(item["value"], item["value_type"]):
                raise ModelError("fact type mismatch")
            provenance = item["provenance"]
            if not isinstance(provenance, dict) or provenance.get("kind") not in PROVENANCE_KINDS - {"observer"}:
                raise ModelError("invalid provenance")
            allowed_provenance = {
                "configured": {"configuration"},
                "user_declared": {"user_declaration"},
                "desired": {"configuration", "user_declaration", "installer"},
                "inferred": {"inference"},
            }
            if provenance["kind"] not in allowed_provenance[item["state_class"]]:
                raise ModelError("state class and provenance disagree")
            if not isinstance(item["owner"], str) or not item["owner"]:
                raise ModelError("invalid owner")
            if item["state_class"] == "inferred":
                inputs = provenance.get("inputs")
                if not isinstance(provenance.get("rule"), str) or not provenance["rule"] or not isinstance(inputs, list) or not inputs or any(not isinstance(ref, list) or len(ref) != 3 or not all(isinstance(part, str) for part in ref) or ref[2] not in STATE_CLASSES for ref in inputs):
                    raise ModelError("inference requires rule and canonical input keys")
            record = dict(item, source=source_id, recorded_at=stamp(at or now()))
            record["provenance"] = dict(provenance, source=source_id)
            slot = key(item["object_id"], item["property"], item["state_class"])
            if slot in new_facts:
                raise ModelError("duplicate source fact")
            new_facts[slot] = record
        for item in snapshot["responsibilities"]:
            if not isinstance(item, dict) or set(item) != {"object_id", "property", "mode", "owner", "provenance"}:
                raise ModelError("invalid responsibility")
            if not _identifier(item["object_id"]) or item["mode"] not in {"watch", "maintain"}:
                raise ModelError("invalid responsibility identity or mode")
            if item["property"] is not None and not isinstance(item["property"], str):
                raise ModelError("invalid responsibility property")
            if not isinstance(item["owner"], str) or not item["owner"]:
                raise ModelError("invalid responsibility owner")
            if not isinstance(item["provenance"], dict) or item["provenance"].get("kind") not in {"configuration", "user_declaration", "installer"}:
                raise ModelError("invalid responsibility source")
            new_responsibilities.append(dict(item, source=source_id, recorded_at=stamp(at or now()), lifecycle="active"))
        new_owners = {record["owner"] for record in new_facts.values()} | {record["owner"] for record in new_responsibilities}
        prior_owners = {record["owner"] for record in self.facts.values() if record.get("source") == source_id} | {record["owner"] for record in self.responsibilities if record.get("source") == source_id}
        if len(new_owners) > 1 or (prior_owners and new_owners and prior_owners != new_owners):
            raise ModelError("source owner mismatch")
        self.revoke_source(source_id)
        self.facts.update(new_facts)
        self.responsibilities.extend(new_responsibilities)

    def revoke_source(self, source_id: str) -> None:
        self.facts = {k: v for k, v in self.facts.items() if v.get("source") != source_id}
        self.responsibilities = [v for v in self.responsibilities if v.get("source") != source_id]

    def observer_failure(self, descriptor: dict[str, Any], owner: str, observer_id: str,
                         reason: str, *, at: datetime | None = None) -> None:
        time = stamp(at or now())
        object_kind = descriptor.get("object_kind")
        failure = {"reason": reason, "at": time, "owner": owner, "observer": observer_id}
        if object_kind in {"mount", "filesystem", "user", "group"}:
            # A failed collection read must never invent objects. Existing
            # observations become stale while retaining their last evidence.
            for slot, fact in self.facts.items():
                if (fact.get("state_class") == "observed" and fact.get("owner") == owner and
                        fact.get("observer") == observer_id and
                        _object_matches_kind(fact.get("object_id"), object_kind)):
                    self.failures[slot] = dict(failure)
        else:
            object_id = _observer_target(descriptor)
            for prop in descriptor["properties"]:
                self.failures[key(object_id, prop["name"], "observed")] = dict(failure)
        self.attempts[observer_id] = {
            "owner": owner, "at": time, "status": "error", "reason": reason
        }

    def _observed_object(
        self,
        descriptor: dict[str, Any],
        owner: str,
        observer_id: str,
        raw: Any,
        *,
        at: datetime,
    ) -> tuple[str, dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
        if not isinstance(raw, dict) or set(raw) != {"object_id", "facts", "unavailable"}:
            raise ModelError("invalid observer object")
        object_id = raw["object_id"]
        if not _object_matches_kind(object_id, descriptor.get("object_kind")):
            raise ModelError("undeclared observer target")
        if not isinstance(raw["facts"], list) or not isinstance(raw["unavailable"], list):
            raise ModelError("invalid observation lists")
        declared = {prop["name"]: prop for prop in descriptor["properties"]}
        seen: set[str] = set()
        updates: dict[str, dict[str, Any]] = {}
        failures: dict[str, dict[str, Any]] = {}
        for item in raw["facts"]:
            if not isinstance(item, dict) or set(item) != {"property", "value", "evidence"}:
                raise ModelError("invalid observed fact")
            prop = item["property"]
            if prop not in declared or prop in seen:
                raise ModelError("duplicate or undeclared observed property")
            seen.add(prop)
            spec = declared[prop]
            value_type = spec["value_type"]
            if (not _typed(item["value"], value_type) or
                    ("minimum" in spec and item["value"] < spec["minimum"])):
                raise ModelError("observation type or range mismatch")
            evidence = item["evidence"]
            if (not isinstance(evidence, list) or len(evidence) > 8 or
                    any(not isinstance(value, str) or len(value) > 200 or
                        any(ord(char) < 32 for char in value) for value in evidence)):
                raise ModelError("invalid evidence")
            slot = key(object_id, prop, "observed")
            updates[slot] = {
                "object_id": object_id,
                "property": prop,
                "state_class": "observed",
                "value": item["value"],
                "value_type": value_type,
                "owner": owner,
                "source": observer_id,
                "observer": observer_id,
                "provenance": {"kind": "observer", "id": observer_id, "evidence": evidence},
                "recorded_at": stamp(at),
                "expires_at": stamp(at + timedelta(seconds=descriptor["freshness_seconds"])),
            }
        for item in raw["unavailable"]:
            if not isinstance(item, dict) or set(item) != {"property", "reason"}:
                raise ModelError("invalid unavailable property")
            prop, reason = item["property"], item["reason"]
            if (prop not in declared or prop in seen or not isinstance(reason, str) or
                    not reason or len(reason) > 200):
                raise ModelError("duplicate or undeclared unavailable property")
            seen.add(prop)
            failures[key(object_id, prop, "observed")] = {
                "reason": reason,
                "at": stamp(at),
                "owner": owner,
                "observer": observer_id,
            }
        if seen != set(declared):
            raise ModelError("incomplete observation result")
        return object_id, updates, failures

    def observe(self, descriptor: dict[str, Any], owner: str, observer_id: str,
                envelope: dict[str, Any], *, at: datetime | None = None) -> None:
        """Validate a complete observer result, then commit it atomically."""
        if (not isinstance(envelope, dict) or set(envelope) != {"status", "result"} or
                envelope["status"] != "ok"):
            raise ModelError("invalid observer envelope")
        result = envelope["result"]
        object_kind = descriptor.get("object_kind")
        time = at or now()

        if object_kind in {"mount", "filesystem", "user", "group"}:
            if not isinstance(result, dict) or set(result) != {"objects"}:
                raise ModelError("invalid collection observer result")
            objects = result["objects"]
            if not isinstance(objects, list) or len(objects) > 128:
                raise ModelError("collection observer result is not bounded")
            updates: dict[str, dict[str, Any]] = {}
            failures: dict[str, dict[str, Any]] = {}
            object_ids: set[str] = set()
            for raw in objects:
                object_id, object_updates, object_failures = self._observed_object(
                    descriptor, owner, observer_id, raw, at=time
                )
                if object_id in object_ids:
                    raise ModelError("duplicate observed object")
                object_ids.add(object_id)
                if set(updates) & set(object_updates) or set(failures) & set(object_failures):
                    raise ModelError("duplicate observed slot")
                updates.update(object_updates)
                failures.update(object_failures)

            prior_fact_slots = {
                slot
                for slot, fact in self.facts.items()
                if fact.get("state_class") == "observed" and fact.get("owner") == owner and
                fact.get("observer") == observer_id and
                _object_matches_kind(fact.get("object_id"), object_kind)
            }
            prior_failure_slots = {
                slot
                for slot, failure in self.failures.items()
                if failure.get("owner") == owner and failure.get("observer") == observer_id
            }
            stale_slots = {
                slot for slot in failures
                if slot in prior_fact_slots
            }
            self.facts = {
                slot: fact
                for slot, fact in self.facts.items()
                if slot not in prior_fact_slots or slot in stale_slots
            }
            self.failures = {
                slot: failure
                for slot, failure in self.failures.items()
                if slot not in prior_failure_slots
            }
            self.facts.update(updates)
            self.failures.update(failures)
            for slot in updates:
                self.failures.pop(slot, None)
            partial = bool(failures)
        else:
            if not isinstance(result, dict) or set(result) != {"object_id", "facts", "unavailable"}:
                raise ModelError("invalid observer result")
            object_id = result["object_id"]
            if object_id != _observer_target(descriptor):
                raise ModelError("undeclared observer target")
            _, updates, failures = self._observed_object(
                descriptor, owner, observer_id, result, at=time
            )
            self.facts.update(updates)
            for slot in updates:
                self.failures.pop(slot, None)
            self.failures.update(failures)
            partial = bool(failures)

        self.attempts[observer_id] = {
            "owner": owner,
            "at": stamp(time),
            "status": "partial" if partial else "ok",
            "reason": "partial" if partial else None,
        }

