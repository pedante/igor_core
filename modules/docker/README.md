# Docker Module v2 experiment

This module is an experiment proving that Igor can gain application abilities
without adding Docker-specific logic to Core.

The module owns Docker concepts:

- containers
- images
- compose projects
- Docker health
- lifecycle intent

Core owns:

- privilege
- approvals
- package installation
- service management
- verification
- platform differences

The first milestone is discovery and read-only inspection. Mutating actions
must be implemented through existing Core capability boundaries.
