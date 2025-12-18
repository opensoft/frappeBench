# Commit Message Summary

## Recent Changes Summary

### Refactor: Separate worktree and site setup phases

- Split monolithic setup script into `setup-worktrees.sh` (host-side) and `setup-apps.sh` (container-side)
- Updated devcontainer.json to run worktrees during initializeCommand and apps during postCreateCommand
- Improved separation of concerns for better reliability across host/container environments

### Config: Migrate from YAML to JSON-only configuration

- Removed YAML dependency from setup scripts
- Renamed `mounts.json` to `frappe-apps.json` for clarity
- Implemented strict JSON validation with clear error messages
- Added temp file-based JSON parsing to avoid shell quoting issues

### Fix: Resolve JSON parsing failures in setup scripts

- Fixed JSON parsing by using temp files instead of stdin pipes
- Added comprehensive error handling for missing configuration files
- Implemented graceful handling of empty or invalid JSON structures

### Docs: Add comprehensive container rebuild diagnostics

- Created `CONTAINER_REBUILD_DIAGNOSTICS.md` with 11 systematic diagnostic checks
- Included automated diagnostic script for quick system assessment
- Added common issues, solutions, and emergency recovery procedures
- Provided configuration reference and environment variable documentation

### Fix: Resolve extension installation conflicts and missing resources

- Added automatic cleanup of leftover extension temp directories in initializeCommand and postCreateCommand
- Removed potentially conflicting `anthropic.url-content-opener` extension
- Created `troubleshoot-extensions.sh` script for diagnosing extension issues
- Updated CONTAINER_REBUILD_DIAGNOSTICS.md with resolution steps for extension conflicts and missing resource files
- Added preventive measures to avoid ENOTEMPTY errors during extension installation

### Config: Create example configuration with full documentation

- Added `frappe-apps.example.json` with all available parameters
- Included detailed comments explaining each configuration option
- Provided examples for both worktree and site configurations

## Suggested Commit Messages

### Option 1 (Comprehensive):

```
refactor: separate worktree and site setup phases

- Split setup into host-side worktrees and container-side apps
- Remove YAML dependency, use JSON-only configuration
- Add strict validation and error handling
- Fix JSON parsing issues with temp file approach
- Add comprehensive container rebuild diagnostics
- Create documented example configuration
```

### Option 2 (Focused):

```
feat: refactor Frappe setup scripts for better reliability

- Separate worktree creation (host) from site setup (container)
- Migrate from YAML to JSON configuration with validation
- Fix JSON parsing failures in setup scripts
- Add diagnostic framework for container rebuild issues
```

### Option 3 (Technical):

```
refactor(setup): separate concerns and improve error handling

- Split setup-worktrees.sh and setup-apps.sh with distinct phases
- Remove YAML dependency, implement JSON validation
- Fix stdin JSON parsing with temp file approach
- Add CONTAINER_REBUILD_DIAGNOSTICS.md for troubleshooting
- Create frappe-apps.example.json with documentation
```

### Option 4 (Minimal):

```
refactor: improve Frappe dev container setup reliability

- Separate worktree and site setup phases
- Use JSON-only config with validation
- Add container rebuild diagnostics
- Fix JSON parsing issues
```

## Files Changed

### Modified:

- `.devcontainer/devcontainer.json` - Updated initializeCommand and postCreateCommand
- `setup-worktrees.sh` - Refactored for worktrees only, added JSON validation
- `setup-apps.sh` - New script for site and app installation
- `frappe-apps.json` - Renamed from mounts.json, updated structure

### Added:

- `frappe-apps.example.json` - Comprehensive example with documentation
- `CONTAINER_REBUILD_DIAGNOSTICS.md` - Diagnostic framework and troubleshooting guide

### Removed:

- YAML dependency from setup scripts
- Old monolithic setup approach

## Testing Notes

- Scripts now validate JSON files before processing
- Worktree setup runs during container initialization
- Site setup runs during post-create phase
- Diagnostic script provides automated system checks
- All changes maintain backward compatibility where possible

## Breaking Changes

- Configuration file renamed from `mounts.json` to `frappe-apps.json`
- Setup scripts now require valid JSON or exit with clear error messages
- YAML configuration no longer supported

## Related Issues

- Resolves container rebuild failures due to YAML parsing
- Fixes worktree conflicts during rebuilds
- Improves error messages for configuration issues
- Provides systematic troubleshooting framework
