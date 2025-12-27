# Tasks: Cache Git-Based Wheels

## Implementation Tasks

### 1. Add wheel cache function to setup-frappe.sh
- [ ] Create `build_git_wheel_cache()` function
- [ ] Define `WHEEL_CACHE_DIR` variable (default: `/tmp/pip-wheel-cache`)
- [ ] Build gunicorn wheel using `pip wheel --no-deps`
- [ ] Export `PIP_FIND_LINKS=$WHEEL_CACHE_DIR`

**Verification:** Function exists and exports environment variable

### 2. Call cache function early in setup flow
- [ ] Call `build_git_wheel_cache()` after `ensure_bench_ready()` but before any pip installs
- [ ] Ensure venv exists before building wheels

**Verification:** Wheel cache directory contains `.whl` file after function runs

### 3. Verify cache inheritance in setup_stack.sh
- [ ] Confirm `PIP_FIND_LINKS` is inherited from parent shell
- [ ] Add fallback export if running standalone

**Verification:** `echo $PIP_FIND_LINKS` shows cache path inside setup_stack.sh

### 4. Test end-to-end
- [ ] Rebuild container from scratch
- [ ] Grep logs for "Cloning https://github.com/frappe/gunicorn"
- [ ] Confirm appears exactly once (during wheel build)

**Verification:** Only 1 gunicorn clone in build output

## Dependencies

```
[1] ──► [2] ──► [3] ──► [4]
```

All tasks are sequential; each depends on the previous.

## Estimated Impact

- **Build time reduction:** 20-30 seconds
- **Files modified:** 2 (setup-frappe.sh, setup_stack.sh)
- **Risk level:** Low
