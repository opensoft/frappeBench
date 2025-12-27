# Proposal: Skip Redundant App Installations

## Summary

Optimize the setup scripts to skip `pip install -e` operations when an app is already installed in editable mode, preventing duplicate package reinstallation during container setup.

## Problem Statement

During container setup, apps are installed multiple times:
1. `setup-frappe.sh` installs apps via `install_bench_apps()`
2. `setup_stack.sh` installs apps again via `ensure_app_python_install()`

Each redundant install:
- Re-resolves all dependencies
- Re-builds any native extensions
- Adds 5-15 seconds per app

With 4 apps (frappe, erpnext, payments, dartwing), this wastes 20-60 seconds.

## Proposed Solution

Before running `pip install -e`, check if the app is already installed in editable mode:

```bash
if pip show -f "$app_name" 2>/dev/null | grep -q "Editable project location"; then
    return 0  # Already installed
fi
```

This check is fast (~100ms) and avoids unnecessary reinstallation.

## Scope

### In Scope
- Adding installation check to `ensure_app_python_install()` in setup_stack.sh
- Adding installation check to `install_bench_apps()` in setup-frappe.sh

### Out of Scope
- Version checking (if installed version differs from source)
- Dependency updates (handled by `bench setup requirements`)
- Non-editable installs

## Success Criteria

- Each app is pip-installed exactly once per container setup
- Setup time reduced by 20-60 seconds (depending on app count)
- No functional changes to installed packages

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Stale install not updated | Low | Low | `bench setup requirements` still runs for dependency updates |
| Check adds overhead | Very Low | Negligible | Check is ~100ms vs 5-15s install |
