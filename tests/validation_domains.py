"""Small, explicit mapping from changed paths to regression test domains.

This is intentionally a reviewable list rather than a dependency graph. When a
change does not match a known domain, callers receive the complete test set.
"""

from __future__ import annotations

from pathlib import Path

_DOMAIN_TESTS: dict[str, tuple[str, ...]] = {
    "documentation": (
        "tests/test_documentation_health.py",
    ),
    "learning": (
        "tests/test_local_learning.py",
        "tests/test_local_learning_integration.py",
        "tests/test_knowledge_artifacts.py",
        "tests/test_knowledge_artifacts_integration.py",
        "tests/test_baselines.py",
        "tests/test_operational_history.py",
        "tests/test_investigations.py",
        "tests/test_context_engine.py",
        "tests/test_context_routing_integration.py",
        "tests/test_capability_runtime.py",
        "tests/test_secret_refs.py",
        "tests/core/test_ai_approval.bats",
        "tests/core/test_ai_privilege.bats",
    ),
    "entrypoint": (
        "tests/test_ai_architecture.py",
        "tests/test_startup_privilege.py",
        "tests/core/test_ai_tui_backend.bats",
    ),
    "capability": (
        "tests/test_module_contract.py",
        "tests/test_input_candidates.py",
        "tests/test_operator_surface.py",
        "tests/test_capability_runtime.py",
        "tests/core/test_safety.bats",
        "tests/core/test_safety_dispatch.bats",
        "tests/core/test_ai_approval.bats",
        "tests/core/test_ai_privilege.bats",
        "tests/core/test_ai_transactions.bats",
        "tests/test_operational_history.py",
        "tests/modules/test_operational_history_dispatch.bats",
        "tests/modules/test_wave_e_capability_dispatch.bats",
        "tests/modules/test_step18_module_contract.bats",
        "tests/modules/test_step18_module_composition.bats",
        "tests/modules/test_s9_cross_module_reuse.bats",
        "tests/modules/test_module_contracts.bats",
        "tests/modules/test_loader_regressions.bats",
        "tests/modules/test_system_admin_surface.bats",
        "tests/test_docker_module.py",
    ),
    "history": (
        "tests/test_operational_history.py",
        "tests/test_deployment_history.py",
        "tests/core/test_ai_events.bats",
        "tests/core/test_ai_event_integration.bats",
        "tests/core/test_ai_safety_events.bats",
        "tests/modules/test_operational_history_dispatch.bats",
    ),
    "module": (
        "tests/test_module_contract.py",
        "tests/test_module_registry.py",
        "tests/test_module_inspection.py",
        "tests/modules/test_module_contracts.bats",
        "tests/modules/test_loader_regressions.bats",
        "tests/modules/test_module_v2.bats",
        "tests/modules/test_step18_module_contract.bats",
        "tests/modules/test_step18_module_composition.bats",
        "tests/modules/test_s9_cross_module_reuse.bats",
        "tests/modules/test_module_conf.bats",
        "tests/modules/test_module_state.bats",
        "tests/modules/test_subsystem_activation.bats",
    ),
    "recognition": (
        "tests/test_resource_recognition.py",
        "tests/test_resource_recognition_adapters.py",
        "tests/test_deployment_attachment.py",
        "tests/test_input_candidates.py",
        "tests/test_module_registry.py",
        "tests/modules/test_deployment_attachment.bats",
    ),
    "configuration": (
        "tests/test_documentation_health.py",
        "tests/test_configuration.py",
        "tests/test_system_configuration_workflow.py",
        "tests/test_secret_refs.py",
        "tests/core/test_config.bats",
    ),
    "openrouter": (
        "tests/test_managed_openrouter.py",
        "tests/test_openrouter_production.py",
        "tests/test_openrouter_import.py",
        "tests/test_secret_refs.py",
        "tests/test_configuration.py",
        "tests/test_system_configuration_workflow.py",
        "tests/test_capability_runtime.py",
        "tests/test_operational_history.py",
        "tests/test_ai_architecture.py",
        "tests/test_context_routing_integration.py",
        "tests/test_ai_settings_backend.py",
        "tests/test_ai_menu_startup.py",
        "tests/core/test_ai_keys.bats",
        "tests/core/test_config.bats",
        "tests/core/test_backup_p2.bats",
        "tests/core/test_backup_regressions.bats",
        "tests/core/test_backup_encryption.bats",
        "tests/core/test_ai_approval.bats",
        "tests/core/test_ai_privilege.bats",
        "tests/core/test_ai_modes.bats",
        "tests/core/test_ai_transactions.bats",
        "tests/core/test_ai_events.bats",
        "tests/core/test_ai_event_integration.bats",
        "tests/core/test_ai_safety_events.bats",
        "tests/core/test_ai_scrub_regressions.bats",
        "tests/test_domain_event.py",
    ),
    "tui": (
        "tests/test_ai_tui.py",
        "tests/test_ai_tui_colors.py",
        "tests/test_operator_surface.py",
        "tests/test_ai_tui_operator.py",
        "tests/test_ai_tui_pty.py",
        "tests/test_ai_tui_privilege.py",
        "tests/test_ai_tui_settings.py",
        "tests/test_ai_tui_step7.py",
        "tests/test_ai_render.py",
        "tests/test_ai_operator_backend.py",
        "tests/test_ai_settings_backend.py",
        "tests/core/test_ai_tui_backend.bats",
    ),
    "operator": (
        "tests/test_input_candidates.py",
        "tests/test_operator_surface.py",
        "tests/test_ai_tui_operator.py",
        "tests/test_ai_operator_backend.py",
    ),
    "deployment": (
        "tests/test_deployments.py",
        "tests/test_deployment_attachment.py",
        "tests/test_deployment_history.py",
        "tests/test_deployment_inspection.py",
        "tests/test_deployment_prerequisites.py",
        "tests/modules/test_deployment_attachment.bats",
    ),
    "events": (
        "tests/test_domain_event.py",
        "tests/core/test_ai_events.bats",
        "tests/core/test_ai_event_integration.bats",
        "tests/modules/test_domain_event_bus.bats",
    ),
    "automation": (
        "tests/test_automation_registry.py",
        "tests/modules/test_healing_activation.bats",
        "tests/integration/test_healing_patterns.bats",
    ),
    "context": (
        "tests/test_context_engine.py",
        "tests/test_context_routing_integration.py",
        "tests/core/test_ai_context_refresh.bats",
        "tests/core/test_ai_host_context.bats",
    ),
    "investigations": (
        "tests/test_investigations.py",
        "tests/test_investigation_inspection.py",
    ),
    "system": (
        "tests/core/test_system_model.py",
        "tests/core/test_host_runtime_query.bats",
        "tests/core/test_network_query.bats",
        "tests/modules/test_system_storage.bats",
        "tests/modules/test_system_admin_surface.bats",
        "tests/modules/test_system_network_read_model.bats",
        "tests/modules/test_system_network_wifi_admin.bats",
        "tests/modules/test_system_runtime_read_model.bats",
        "tests/modules/test_step18_module_composition.bats",
        "tests/modules/test_s9_cross_module_reuse.bats",
        "tests/test_host_runtime_query.py",
        "tests/test_network_query.py",
        "tests/test_networkmanager_wifi.py",
        "tests/test_module_registry.py",
        "tests/test_system_network_surface.py",
        "tests/test_docker_module.py",
    ),
}

_RECOGNITION_PATHS = frozenset({
    "core/lib/resource_recognition.py",
    "modules/nextcloud_docker/lib/nextcloud_recognition.py",
    "modules/samba/lib/samba_recognition.py",
})

_PATH_DOMAINS: tuple[tuple[tuple[str, ...], str], ...] = (
    (("openrouter", "secret_refs", "core/ai/keys.sh", "core/ai/api.sh", "core/ai/core.sh",
      "core/ai/ai_engine.py", "core/ai/privacy.py", "core/ai/request_boundary.py", "core/ai/control.sh", "core/ai/safety.sh",
      "core/ai/events.sh", "core/lib/domain_event.py",
      "core/lib/ai_hybrid.sh", "core/lib/config_loader.sh", "core/recovery/config_backup.sh",
      "core/recovery/full_backup.sh", "core/lib/configuration.py",
      "core/lib/configuration.sh", "core/lib/configuration_schema.py"), "openrouter"),
    (("local_learning", "knowledge_artifact"), "learning"),
    (("capability", "capabilities", "approval", "safety", "privilege", "package", "core/lib/pkg.sh", "service_admission", "input_candidates", "operator_surface", "core/ai/core.sh", "modules/docker/", "modules/system/"), "capability"),
    (("operational_history", "history"), "history"),
    (("module_contract", "module_loader", "module_registry", "module_contracts", "module_v2", "modules/"), "module"),
    (("config", "secret", "variables"), "configuration"),
    (("operator_surface", "input_candidates", "operator_backend", "core/ai/core.sh"), "operator"),
    (("tui", "frontend", "ai_render", "ai_settings", "core/ai/core.sh"), "tui"),
    (("deployment", "deployments", "nextcloud_docker/lib/attachment"), "deployment"),
    (("domain_event", "event_bus", "ai_events", "core/ai/events.sh"), "events"),
    (("automation", "healing", "judgment"), "automation"),
    (("context", "host_context"), "context"),
    (("investigation", "investigations"), "investigations"),
    (("system_model", "host_runtime_query", "core/lib/host_runtime.sh", "network_query", "networkmanager_wifi", "core/lib/network.sh", "modules/system", "modules/docker", "docker"), "system"),
)


def _all_tests(root: Path) -> set[str]:
    tests = root / "tests"
    return {
        path.relative_to(root).as_posix()
        for pattern in ("test_*.py", "test_*.bats")
        for path in tests.rglob(pattern)
        if path.is_file()
    }


def affected_tests(paths: list[str], root: Path) -> tuple[list[str], list[str]]:
    """Return sorted domain labels and test paths relevant to changed paths."""
    root = root.resolve()
    domains: set[str] = set()
    selected: set[str] = set()
    all_tests = _all_tests(root)
    root_entrypoint_seen = False
    mapped_implementation_seen = False

    for raw_path in paths:
        path = Path(raw_path)
        if path.is_absolute():
            try:
                relative = path.resolve().relative_to(root).as_posix()
            except ValueError:
                domains.add("all")
                selected.update(all_tests)
                continue
        else:
            relative = path.as_posix().removeprefix("./")

        if relative.startswith("docs/") or relative.endswith((".md", ".rst")):
            domains.add("documentation")
            selected.update(_DOMAIN_TESTS["documentation"])
            continue

        if relative.startswith("tests/") and Path(relative).name.startswith("test_"):
            if relative in all_tests:
                selected.add(relative)
                domains.add("validation" if "validation_" in Path(relative).name else "tests")
            continue

        if relative.startswith("tests/helpers/") or relative == "tests/run_all.sh":
            domains.add("all")
            selected.update(all_tests)
            continue

        if relative == ".github/workflows/ci.yml" or relative == "tests/validate.sh" or (relative.startswith("tests/") and "validation" in Path(relative).name):
            domains.add("validation")
            selected.update(p for p in all_tests if p.startswith("tests/test_validation_"))
            continue

        # igor.sh is a shared CLI/router. A root-only edit remains broad because
        # its impact is ambiguous, but when a feature change also touches a
        # recognized implementation domain we add direct entrypoint regressions
        # without letting this thin facade force the entire repository suite.
        if relative == "igor.sh":
            root_entrypoint_seen = True
            domains.add("entrypoint")
            selected.update(_DOMAIN_TESTS["entrypoint"])
            continue

        # This private read-only seam has a reviewed, bounded coverage map.
        # In particular, dormant domain adapters are not a new module loader
        # or public Module API change. Preserve "all" for every unknown path.
        if relative in _RECOGNITION_PATHS:
            mapped_implementation_seen = True
            domains.add("recognition")
            selected.update(_DOMAIN_TESTS["recognition"])
            continue

        matches = [domain for tokens, domain in _PATH_DOMAINS if any(token in relative.lower() for token in tokens)]
        if matches:
            mapped_implementation_seen = True
            for domain in matches:
                domains.add(domain)
                selected.update(_DOMAIN_TESTS[domain])
            continue

        # Unknown implementation changes receive broad coverage. This is the
        # deliberate safe fallback until an explicit domain is added.
        domains.add("all")
        selected.update(all_tests)

    if root_entrypoint_seen and not mapped_implementation_seen and "all" not in domains:
        # Preserve the safe fallback for standalone root-entrypoint changes.
        domains.add("all")
        selected.update(all_tests)

    selected.intersection_update(all_tests)
    return sorted(domains), sorted(selected)
