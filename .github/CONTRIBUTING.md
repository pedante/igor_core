# Contributing to IGOR

Thank you for your interest in contributing to IGOR! This guide will help you get started.

## Quick Start

1. **Fork the repository** and create your feature branch
   ```bash
   git clone https://github.com/[your-username]/igor.git
   cd igor
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Follow the existing code style and conventions
   - Add tests for new functionality
   - Update documentation as needed

3. **Run tests**
   ```bash
   cd tests
   bats test_safety.sh
   bats test_providers.sh
   ```
   All tests should pass before submitting a PR

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "Add your feature"
   ```

5. **Push and create Pull Request**
   ```bash
   git push origin feature/your-feature-name
   # Then create PR via GitHub web interface
   ```

## Development Workflow

### Code Style

- **Bash:** Follow existing patterns in `lib/`, `modules/`, `ai/`, `healing/`
- **Function naming:**
  - Module public functions: `menu_X()` (e.g., `menu_install()`)
  - Module private functions: `_mod_X_*()` (e.g., `_mod_install_ensure_secrets()`)
  - AI subsystem: `ai_*()` or `_ai_*()` for private
  - Healing subsystem: `healing_*()` or `_healing_*()` for private
- **Comments:** Add comments for complex logic; move hard-won lessons to docs
- **Indentation:** Use 4 spaces for indentation (not tabs)

### Adding Features

1. **Add tests** for new functionality to `tests/` directory
2. **Update documentation** in `docs/` if changes affect architecture or user-facing behavior
3. **Follow plugin contracts** when adding new providers or checks
4. **Test on target platform** (Raspberry Pi 3) when possible

### Adding AI Providers

Follow the [Adding a Provider](../docs/adding-a-provider.md) guide:

1. Create provider file: `ai/providers/[name].sh`
2. Implement contract functions:
   - `_provider_get_endpoint()` - Return API endpoint URL
   - `_provider_get_headers()` - Return HTTP headers
   - `_provider_build_request()` - Build request body (if needed)
   - `_provider_parse_stream()` - Parse SSE stream (if needed)
3. Add tests to `tests/test_providers.sh`
4. Update provider documentation

See also: [adding-a-provider.md](../docs/adding-a-provider.md)

### Adding Health Checks

Follow the [Adding a Check](../docs/adding-a-check.md) guide:

1. Create check file: `healing/checks/[name].sh`
2. Implement `run_check()` function:
   - Returns status: ok/warn/fail
   - Returns message: human-readable description
   - Returns severity: OK/WARN/FAIL/CRITICAL
   - Returns suggested_repair: command or action to fix issue
3. Add tests for the check
4. Update check documentation

See also: [adding-a-check.md](../docs/adding-a-check.md)

## Testing

### Running Tests

IGOR uses BATS (Bash Automated Testing System) for testing.

**Install BATS:**
```bash
# Ubuntu/Debian:
sudo apt-get install bats

# macOS:
brew install bats-core

# Other: https://bats-core.readthedocs.io/
```

**Run all tests:**
```bash
cd tests
bats test_safety.sh
bats test_providers.sh
```

**Run specific test file:**
```bash
bats tests/test_safety.sh
bats tests/test_providers.sh
```

### Test Requirements

- All new features must include tests
- Tests must pass before PR submission
- Test coverage should match the scope of changes
- Edge cases should be considered

## Documentation

If your change affects user-facing behavior:

- Update [docs/ARCHITECTURE.md](ARCHITECTURE.md) if architecture changes
- Add to [docs/troubleshooting.md](troubleshooting.md) if new failure modes
- Update [docs/dynamic-menu-items.md](dynamic-menu-items.md) if dynamic items change
- Update relevant plugin docs (adding-a-provider.md, adding-a-check.md)

## Submitting a Pull Request

Before submitting your PR:

- [x] Tests pass locally
- [x] Documentation updated
- [x] Code follows project style guidelines
- [x] Commit messages are clear and descriptive
- [x] PR description explains what and why

## PR Template

When creating a Pull Request, please include:

### Description
- What does this PR do?
- Why is it needed?
- How does it solve the problem?

### Testing
- How did you test this change?
- What tests did you add or modify?
- Did all tests pass?

### Checklist
- [ ] Tests pass for all affected functionality
- [ ] Documentation updated if needed
- [ ] Code follows project conventions
- [ ] No merge conflicts expected

## Questions?

- Check existing [Issues](https://github.com/[username]/igor/issues) for known bugs
- Review [docs/ARCHITECTURE.md](ARCHITECTURE.md) for system design
- See [docs/troubleshooting.md](troubleshooting.md) for common problems

## Code Review

All PRs are reviewed by maintainers. We may:

- Request changes for code style or clarity
- Suggest additional tests or documentation
- Discuss alternative approaches

This is to ensure code quality and maintainability of the project.

## License

By contributing, you agree that your contributions will be licensed under the [GPL v3](../LICENSE) license.
