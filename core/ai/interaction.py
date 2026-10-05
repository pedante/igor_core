"""Private presentation primitives; no storage, policy or execution handles.

Property schemas describe controls, never commands or storage locations. A
proposal is detached typed data that an owning backend adapter must validate.
"""

from __future__ import annotations

import copy
import math
import re
from dataclasses import dataclass
from typing import Any

REGIONS = ("input", "output", "panel")
PROPERTY_TYPES = frozenset({"text", "enum", "boolean", "integer", "number"})
_SECRET_KEYS = frozenset({"password", "secret", "secret_value", "api_key",
                          "access_token", "authorization", "credential"})


def display_text(value: Any, limit: int = 240) -> str:
    """Keep inspection metadata on one bounded terminal line."""
    return "".join(char if char.isprintable() else " " for char in str(value))[:limit]


def _finite(value: Any) -> bool:
    try:
        return type(value) in (int, float) and math.isfinite(value)
    except OverflowError:
        return False


@dataclass
class FocusModel:
    """Disposable UI focus; opening/closing a panel preserves the draft."""

    region: str = "input"
    panel_open: bool = False
    panel_selection: int = 0
    panel_scroll: int = 0

    def set_focus(self, region: str) -> None:
        if region not in REGIONS or (region == "panel" and not self.panel_open):
            raise ValueError("unavailable focus region")
        self.region = region

    def cycle(self, reverse: bool = False) -> None:
        regions = REGIONS if self.panel_open else REGIONS[:2]
        self.region = regions[(regions.index(self.region) + (-1 if reverse else 1)) % len(regions)]

    def toggle_panel(self) -> None:
        self.panel_open = not self.panel_open
        if self.panel_open:
            self.region = "panel"
        elif self.region == "panel":
            self.region = "input"

    def select(self, delta: int, count: int) -> None:
        self.panel_selection = min(max(0, count - 1), max(0, self.panel_selection + delta))
        self.panel_scroll = 0


@dataclass(frozen=True)
class Property:
    id: str
    label: str
    type: str
    value: Any
    available: bool
    editable: bool
    source: str
    secret: bool = False
    options: tuple[Any, ...] = ()
    minimum: float | None = None
    maximum: float | None = None
    max_length: int = 1024


def parse_property(schema: Any) -> Property:
    """Strict, small presentation schema; unknown control types fail closed."""
    allowed = {"id", "label", "type", "value", "editable", "source", "secret",
               "options", "minimum", "maximum", "max_length"}
    if not isinstance(schema, dict) or schema.keys() - allowed:
        raise ValueError("unsupported property schema")
    identifier, kind = schema.get("id"), schema.get("type")
    if (not isinstance(identifier, str) or not re.fullmatch(r"[a-zA-Z0-9_.:-]{1,160}", identifier)
            or not isinstance(kind, str) or kind not in PROPERTY_TYPES):
        raise ValueError("unsupported property identity/type")
    for key in ("editable", "secret"):
        if key in schema and type(schema[key]) is not bool:
            raise ValueError("invalid property flags")
    label, source = schema.get("label", identifier), schema.get("source", "unavailable")
    if not isinstance(label, str) or not isinstance(source, str):
        raise TypeError("invalid property metadata")
    options = schema.get("options", [])
    if (not isinstance(options, (list, tuple)) or len(options) > 32
            or any(not isinstance(item, str) or len(item) > 1024 for item in options)):
        raise ValueError("invalid property options")
    if kind == "enum" and not options:
        raise ValueError("enum requires options")
    low, high = schema.get("minimum"), schema.get("maximum")
    for bound in (low, high):
        if bound is not None and not _finite(bound):
            raise ValueError("invalid property bounds")
    if low is not None and high is not None and low > high:
        raise ValueError("invalid property bounds")
    length = schema.get("max_length", 1024)
    if type(length) is not int or not 1 <= length <= 4096:
        raise ValueError("invalid property length")
    secret = schema.get("secret", False) or identifier.lower() in _SECRET_KEYS
    available = "value" in schema
    prop = Property(identifier, label, kind, None if secret else copy.deepcopy(schema.get("value")),
                    available, schema.get("editable", False) and available and not secret,
                    source, secret, tuple(options), low, high, length)
    if available and not secret:
        validate_value(prop, prop.value)
    return prop


def validate_value(prop: Property, value: Any) -> Any:
    if prop.type in {"text", "enum"}:
        if (not isinstance(value, str) or len(value) > prop.max_length
                or any(not char.isprintable() for char in value)):
            raise ValueError("value must be bounded single-line text")
        if prop.type == "enum" and value not in prop.options:
            raise ValueError("value is not an allowed option")
    elif prop.type == "boolean":
        if type(value) is not bool:
            raise ValueError("value must be boolean")
    elif prop.type in {"integer", "number"}:
        if (not _finite(value)
                or (prop.type == "integer" and type(value) is not int)):
            raise ValueError("value must be a finite " + prop.type)
        if ((prop.minimum is not None and value < prop.minimum)
                or (prop.maximum is not None and value > prop.maximum)):
            raise ValueError("value is outside presentation bounds")
    else:
        raise ValueError("unsupported control type")
    return copy.deepcopy(value)


def parse_control_input(prop: Property, text: str) -> Any:
    """Convert editor text to typed data, never evaluate expressions."""
    if prop.type == "boolean":
        if text not in {"true", "false"}:
            raise ValueError("value must be true or false")
        value: Any = text == "true"
    elif prop.type == "integer":
        try:
            value = int(text)
        except (ValueError, TypeError):
            raise ValueError("value must be an integer") from None
    elif prop.type == "number":
        try:
            value = float(text)
        except (ValueError, TypeError):
            raise ValueError("value must be a number") from None
    else:
        value = text
    return validate_value(prop, value)


def propose_property(prop: Property, value: Any) -> dict[str, Any]:
    if not prop.editable or prop.secret:
        raise ValueError("property is read-only")
    return {"property_id": prop.id, "value": validate_value(prop, value)}


def property_text(prop: Property) -> str:
    if prop.secret:
        value = "[secret hidden]"
    elif not prop.available:
        value = "[unavailable]"
    elif prop.type == "boolean":
        value = "On" if prop.value else "Off"
    else:
        value = display_text(prop.value)
    return f"{display_text(prop.label)} [{prop.type}]: {value}"


def render_properties(schemas: Any) -> list[str]:
    if not isinstance(schemas, list) or len(schemas) > 64:
        return ["Invalid property schema"]
    rows = []
    for schema in schemas:
        try:
            prop = parse_property(schema)
            rows.extend([property_text(prop),
                         f"  {'editable' if prop.editable else 'read-only'} · source: {display_text(prop.source)}"])
        except (ValueError, TypeError, OverflowError):
            rows.append("Invalid/unsupported property")
    return rows or ["No properties supplied"]


def render_structured(
    data: Any,
    *,
    max_rows: int = 200,
    max_depth: int = 6,
    root_label: str = "backend",
) -> list[str]:
    """Bounded read-only rendering for already sanitized inspection results."""
    rows: list[str] = []
    seen: set[int] = set()

    def visit(value: Any, label: str, depth: int, hidden: bool = False) -> None:
        if len(rows) >= max_rows:
            return
        prefix = "  " * depth + display_text(label, 100)
        if hidden:
            rows.append(prefix + ": [secret hidden]")
        elif isinstance(value, (dict, list)):
            if id(value) in seen or depth >= max_depth:
                rows.append(prefix + ": [bounded]")
                return
            seen.add(id(value))
            rows.append(prefix + (":" if value else ": (empty)"))
            marked_secret = isinstance(value, dict) and value.get("secret") is True
            items = value.items() if isinstance(value, dict) else enumerate(value)
            for key, child in items:
                visit(child, str(key), depth + 1,
                      str(key).lower() in _SECRET_KEYS or (marked_secret and key == "value"))
                if len(rows) >= max_rows:
                    break
            seen.remove(id(value))
        elif isinstance(value, str) and ("\n" in value or "\r" in value):
            rows.append(prefix + ":")
            continuation = "  " * (depth + 1)
            for line in value.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
                if len(rows) >= max_rows:
                    break
                rows.append(continuation + display_text(line, 400))
        elif value is None or type(value) in (str, int, float, bool):
            rows.append(prefix + ": " + display_text(value))
        else:
            rows.append(prefix + ": [unsupported]")

    visit(data, root_label, 0)
    if len(rows) == max_rows:
        rows[-1] = "[inspection display bounded]"
    return rows
