# Tasks: Skip Redundant App Installations

## Implementation Tasks

### 1. Add is_app_installed helper function
- [ ] Create `is_app_installed()` function that checks editable install status
- [ ] Use `pip show -f` to check for "Editable project location"
- [ ] Return 0 if installed, 1 if not

**Verification:** Function correctly identifies installed vs not-installed apps

### 2. Update ensure_app_python_install in setup_stack.sh
- [ ] Call `is_app_installed` before `pip install -e`
- [ ] Log skip message when already installed
- [ ] Preserve existing behavior for non-installed apps

**Verification:** Running setup_stack.sh twice shows "already installed" on second run

### 3. Update install_bench_apps in setup-frappe.sh
- [ ] Add same installation check before pip install
- [ ] Log skip message when already installed

**Verification:** Logs show skip messages for already-installed apps

### 4. Test end-to-end
- [ ] Rebuild container from scratch
- [ ] Count pip install operations in logs
- [ ] Confirm each app installed exactly once

**Verification:** "pip install -e" appears once per app in build output

## Dependencies

```
[1] ──► [2] ──┐
             ├──► [4]
[1] ──► [3] ──┘
```

- Task 1 must complete first (shared helper)
- Tasks 2 and 3 can run in parallel
- Task 4 requires both 2 and 3

## Estimated Impact

- **Build time reduction:** 20-60 seconds (varies by app count)
- **Files modified:** 2 (setup-frappe.sh, setup_stack.sh)
- **Risk level:** Low
