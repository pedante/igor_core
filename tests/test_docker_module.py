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
    assert by_id["docker.container.list"]["requires"]["bins"] == ["docker"]
    assert by_id["docker.container.restart"]["safety"]["tier"] == "CHANGE"
    assert by_id["docker.container.restart"]["requires"]["bins"] == ["docker"]

    install = by_id["docker.install"]
    assert install["kind"] == "plan"
    assert install["plan_version"] == 1
    assert "handler" not in install
    assert [step["capability_id"] for step in install["steps"]] == [
        "system.package.install",
        "system.service.enable",
        "system.service.start",
    ]
    assert install["steps"][0]["inputs"] == {"package": "pkg_docker"}
    assert install["steps"][1]["inputs"] == {"unit": "docker.service"}
    assert install["steps"][2]["inputs"] == {"unit": "docker.service"}
    assert install["requires"]["capabilities"] == [
        "system.package.install",
        "system.service.enable",
        "system.service.start",
    ]


def test_docker_module_does_not_claim_package_or_service_mechanisms():
    module = (ROOT / "modules" / "docker" / "module.sh").read_text()
    forbidden = ("apt-get ", " apt ", "pacman ", "systemctl ", "sudo ",
                 "usermod ", "docker group", "groupadd ")
    assert all(token not in module for token in forbidden)
