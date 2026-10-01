"""Deterministic provider-neutral model role routing contract."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "core" / "ai"))

from model_roles import route_model

PRIMARY = {"provider": "ollama", "model": "local-reasoner", "tools": True,
           "output_formats": ["text", "json"]}


def test_request_rules_are_deterministic_and_inspectable():
    for request, role, rule in [
        ("conversation", "reasoner", "conversation_reasoner"),
        ("operational", "reasoner", "operational_reasoner"),
        ("unclassified", "reasoner", "default_reasoner"),
        ("summarize", "summarizer", "conversation_summarization"),
    ]:
        decision = route_model(request, PRIMARY)
        assert decision["status"] == "selected"
        assert decision["requested_role"] == decision["selected_role"] == role
        assert decision["rule"] == rule
        assert (decision["provider"], decision["model"]) == ("ollama", "local-reasoner")
    assert route_model("inspect", PRIMARY)["status"] == "no_model"
    assert route_model("local", PRIMARY)["selected_role"] is None
    assert route_model("other", PRIMARY)["status"] == "invalid"


def test_role_binding_overrides_primary_and_ranker_requires_explicit_json_binding():
    decision = route_model("conversation", PRIMARY,
                           {"reasoner": {"provider": "anthropic", "model": "configured-model"}})
    assert (decision["provider"], decision["model"]) == ("anthropic", "configured-model")

    no_ranker = route_model("rank_context", PRIMARY)
    assert no_ranker["requested_role"] == "context_ranker"
    assert no_ranker["status"] == "unavailable"
    assert no_ranker["fallback"] == "deterministic_selection"

    ranker = route_model("rank_context", PRIMARY,
                         {"context_ranker": {"provider": "openrouter", "model": "ranker",
                                             "output_formats": ["json"], "tools": True}})
    assert ranker["selected_role"] == "context_ranker"
    assert ranker["required_output"] == "json"
    assert ranker["tools_allowed"] is False


def test_disabled_unavailable_and_constraint_failures_are_safe():
    disabled = route_model("conversation", PRIMARY, enabled=False)
    assert disabled["status"] == "disabled"
    assert disabled["provider"] is None
    unavailable = route_model("conversation", PRIMARY, available_providers=set())
    assert unavailable["status"] == "unavailable"
    assert unavailable["provider"] is None
    over_budget = route_model("conversation", PRIMARY, context_tokens=11, context_budget=10)
    assert over_budget["status"] == "context_budget_exceeded"
    no_tools = route_model("operational", {"provider": "ollama", "model": "m",
                                            "tools": False}, tools_allowed=True)
    assert no_tools["status"] == "unavailable"
    no_json = route_model("rank_context", PRIMARY,
                          {"context_ranker": {"provider": "ollama", "model": "m",
                                              "output_formats": ["text"]}})
    assert no_json["status"] == "unavailable"
    assert no_json["fallback"] == "deterministic_selection"


def test_invalid_configuration_is_closed_and_provenance_contains_no_binding_secrets():
    malformed = route_model("conversation", {"provider": "openai", "model": "do-not-expose"})
    assert malformed["status"] == "invalid"
    assert "do-not-expose" not in json.dumps(malformed)
    assert route_model("conversation", PRIMARY, {"unexpected": {}})["status"] == "invalid"
