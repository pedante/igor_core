"""Provider-neutral, deterministic model role selection.

This module records a routing decision only. It does not probe providers,
invoke models, retry requests, execute tools, approve actions, or mutate Igor
state. Binding availability is configuration supplied by the caller.
"""

from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any

POLICY_VERSION = 1
ROLES = {"reasoner", "summarizer", "context_ranker"}
PROVIDERS = {"anthropic", "openrouter", "ollama"}
REQUEST_RULES = {
    "conversation": ("reasoner", "conversation_reasoner"),
    "operational": ("reasoner", "operational_reasoner"),
    "unclassified": ("reasoner", "default_reasoner"),
    "summarize": ("summarizer", "conversation_summarization"),
    "rank_context": ("context_ranker", "context_relevance_ranking"),
    "inspect": (None, "local_inspection"),
    "local": (None, "local_operation"),
}


def _decision(request_type: str, rule: str, role: str | None, reason: str,
              status: str, *, provider: str | None = None,
              model: str | None = None, fallback: str | None = None,
              context_tokens: int | None = None,
              context_budget: int | None = None,
              required_output: str = "text", tools_allowed: bool = False) -> dict[str, Any]:
    """Return a detached, JSON-safe, bounded provenance record."""
    result = {
        "policy_version": POLICY_VERSION,
        "request_type": request_type if request_type in REQUEST_RULES else "invalid",
        "rule": rule,
        "requested_role": role,
        "selected_role": role if status == "selected" else None,
        "provider": provider,
        "model": model,
        "status": status,
        "reason": reason,
        "fallback": fallback,
        "context_tokens": context_tokens,
        "context_budget": context_budget,
        "required_output": required_output,
        "tools_allowed": tools_allowed,
    }
    # Keep this contract finite and safe to persist/emit as operational metadata.
    return json.loads(json.dumps(result, separators=(",", ":")))


def _valid_binding(binding: object) -> bool:
    if not isinstance(binding, Mapping) or not {"provider", "model"} <= binding.keys():
        return False
    if set(binding) - {"provider", "model", "enabled", "available", "output_formats", "tools"}:
        return False
    provider, model = binding.get("provider"), binding.get("model")
    if (type(provider) is not str or provider not in PROVIDERS or type(model) is not str
            or not model or len(model) > 160 or any(ord(char) < 32 for char in model)):
        return False
    for flag in ("enabled", "available", "tools"):
        if flag in binding and type(binding[flag]) is not bool:
            return False
    formats = binding.get("output_formats")
    return formats is None or (type(formats) is list and bool(formats) and
                               all(type(value) is str and value in {"text", "json"}
                                   for value in formats))


def route_model(request_type: str, primary_binding: Mapping[str, Any] | None,
                role_bindings: Mapping[str, Mapping[str, Any]] | None = None, *,
                enabled: bool = True, available_providers: set[str] | frozenset[str] | None = None,
                context_tokens: int = 0, context_budget: int | None = None,
                required_output: str = "text", tools_allowed: bool = False) -> dict[str, Any]:
    """Select an explicitly configured role binding and explain the rule.

    `available_providers`, when supplied, is a caller-owned configuration
    snapshot; this function never checks provider health. A role binding can
    override the primary binding. Summarization inherits the primary binding;
    context ranking requires its own explicit binding.
    """
    if type(request_type) is not str or request_type not in REQUEST_RULES:
        return _decision("invalid", "closed_request_type", None, "unsupported request type", "invalid")
    role, rule = REQUEST_RULES[request_type]
    if role is None:
        return _decision(request_type, rule, None, "request is handled locally", "no_model")
    if type(enabled) is not bool:
        return _decision(request_type, rule, role, "AI enablement configuration is invalid", "invalid")
    if type(context_tokens) is not int or context_tokens < 0 or (
            context_budget is not None and (type(context_budget) is not int or context_budget < 0)):
        return _decision(request_type, rule, role, "context budget metadata is invalid", "invalid")
    if type(required_output) is not str or required_output not in {"text", "json"} or type(tools_allowed) is not bool:
        return _decision(request_type, rule, role, "role requirements are invalid", "invalid")
    if context_budget is not None and context_tokens > context_budget:
        return _decision(request_type, rule, role, "context exceeds configured budget",
                         "context_budget_exceeded", context_tokens=context_tokens,
                         context_budget=context_budget, required_output=required_output,
                         tools_allowed=tools_allowed)
    if not enabled:
        return _decision(request_type, rule, role, "AI is disabled by configuration", "disabled",
                         context_tokens=context_tokens, context_budget=context_budget,
                         required_output=required_output, tools_allowed=tools_allowed)

    if role_bindings is None:
        role_bindings = {}
    if not isinstance(role_bindings, Mapping) or set(role_bindings) - ROLES:
        return _decision(request_type, rule, role, "role binding configuration is invalid", "invalid")
    binding = role_bindings.get(role)
    if binding is None and (role == "reasoner" or role == "summarizer"):
        binding = primary_binding
    if binding is None:
        return _decision(request_type, rule, role, "role has no explicit configured binding",
                         "unavailable", fallback="deterministic_selection" if role == "context_ranker" else None,
                         context_tokens=context_tokens, context_budget=context_budget,
                         required_output=required_output, tools_allowed=tools_allowed)
    if not _valid_binding(binding):
        return _decision(request_type, rule, role, "role binding is invalid", "invalid",
                         context_tokens=context_tokens, context_budget=context_budget)
    provider, model = binding["provider"], binding["model"]
    if binding.get("enabled", True) is False:
        return _decision(request_type, rule, role, "role binding is disabled", "unavailable",
                         fallback="deterministic_selection" if role == "context_ranker" else None,
                         context_tokens=context_tokens, context_budget=context_budget)
    if binding.get("available", True) is False or (
            available_providers is not None and provider not in available_providers):
        return _decision(request_type, rule, role, "configured provider is unavailable", "unavailable",
                         fallback="deterministic_selection" if role == "context_ranker" else None,
                         context_tokens=context_tokens, context_budget=context_budget)

    output = "json" if role == "context_ranker" else required_output
    formats = binding.get("output_formats")
    if formats is not None and output not in formats:
        return _decision(request_type, rule, role, "binding does not support required output", "unavailable",
                         fallback="deterministic_selection" if role == "context_ranker" else None,
                         context_tokens=context_tokens, context_budget=context_budget,
                         required_output=output)
    effective_tools = tools_allowed if role == "reasoner" else False
    if effective_tools and binding.get("tools", False) is not True:
        return _decision(request_type, rule, role, "binding does not permit required tools", "unavailable",
                         context_tokens=context_tokens, context_budget=context_budget,
                         required_output=output, tools_allowed=effective_tools)
    return _decision(request_type, rule, role, "selected by deterministic request rule", "selected",
                     provider=provider, model=model, context_tokens=context_tokens,
                     context_budget=context_budget, required_output=output,
                     tools_allowed=effective_tools)
