#!/usr/bin/env python3
"""The Docker experiment must remain a native Module API v2 package."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "core" / "lib"))

from module_contract import validate_module  # noqa: E402


def test_docker_module_validates_as_v2_package():
    data = validate_module(ROOT / "modules" / "docker")
    manifest = data["manifest"]
    assert manifest["module_api"] == 2
    assert manifest["name"] == "docker"
    assert manifest["compat"]["v1_hooks"] is False
    assert manifest["contracts"] == ["contracts/docker.json"]

    by_id = {row["id"]: row for row in data["contributions"]}
    assert set(by_id) == {
        "docker.status",
        "docker.container.list",
        "docker.container.restart",
        "docker.install",
    }
    assert by_id["docker.status"]["safety"]["tier"] == "READ"
    assert by_id["docker.container.list"]["safety"]["tier"] == "READ"
    assert by_id["docker.container.restart"]["safety"]["tier"] == "CHANGE"
    assert by_id["docker.container.restart"]["requires"]["bins"] == ["docker"]
    assert by_id["docker.install"]["safety"]["tier"] == "CHANGE"
    assert by_id["docker.install"]["privilege"] == "none"
    assert "handler" not in by_id["docker.install"]
    assert by_id["docker.install"]["implementation"]["kind"] == "composition"
    assert by_id["docker.install"]["requires"]["capabilities"] == [
        "system.package.install",
        "system.service.enable",
        "system.service.start",
    ]
    variants = by_id["docker.install"]["implementation"]["variants"]
    assert variants[0]["requires"]["platform_families"] == ["debian"]
    assert variants[0]["steps"][0]["inputs"]["package"] == "docker.io"
    assert variants[1]["requires"]["platform_families"] == ["arch"]
    assert variants[1]["steps"][0]["inputs"]["package"] == "docker"
    assert by_id["docker.install"]["implementation"]["final_check"]["capability_id"] == "docker.status"
    assert by_id["docker.install"]["implementation"]["final_check"]["expect"] == {
        "installed": True,
        "daemon_accessible": True,
    }


def test_docker_module_does_not_claim_package_or_service_mechanisms():
    module = (ROOT / "modules" / "docker" / "module.sh").read_text()
    forbidden = ("apt-get ", " apt ", "pacman ", "systemctl ", "sudo ")
    assert all(token not in module for token in forbidden)
