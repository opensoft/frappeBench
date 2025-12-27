# Proposal: Cache Git-Based Wheels During Setup

## Summary

Pre-build git-based Python wheels (specifically the frappe/gunicorn fork) once at the start of container setup and configure pip to reuse them for all subsequent installs, eliminating redundant git clones.

## Problem Statement

During container setup, the gunicorn package from `git+https://github.com/frappe/gunicorn@bb554053bb...` is cloned 3 separate times:
1. When installing frappe app
2. When installing dartwing app
3. During repeated `pip install -e` calls in setup_stack.sh

Each clone fetches the same repository content, wasting:
- ~10-15 seconds per clone (30-45 seconds total)
- Network bandwidth
- Disk I/O during extraction

## Proposed Solution

1. Create a wheel cache directory at `/tmp/pip-wheel-cache`
2. Before any app installation, pre-build wheels for known git-based dependencies
3. Export `PIP_FIND_LINKS` environment variable to point pip at the cache
4. All subsequent `pip install` commands automatically use cached wheels

## Scope

### In Scope
- Caching the frappe/gunicorn fork wheel
- Modifying `setup-frappe.sh` to build and export wheel cache
- Ensuring `setup_stack.sh` inherits the cache configuration

### Out of Scope
- Caching other git-based dependencies (can be added later)
- Persistent wheel cache across container rebuilds (would require volume mount)
- Upstream contribution to frappe to use standard gunicorn

## Success Criteria

- Gunicorn is cloned exactly once per container setup
- Setup time reduced by 20-30 seconds
- No functional changes to installed packages

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Wheel cache not inherited by subprocesses | Low | Medium | Export PIP_FIND_LINKS before any pip calls |
| Wheel incompatibility | Very Low | Low | Build wheel in same venv that will use it |
