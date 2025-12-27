# Spec Delta: Build Optimization - Wheel Caching

## ADDED Requirements

### Requirement: Git-based wheel caching

The setup scripts SHALL pre-build wheels for git-based dependencies before installing apps, and configure pip to use the cached wheels for all subsequent installations.

#### Scenario: First-time container setup with gunicorn dependency

**Given** a fresh container with no wheel cache
**When** `setup-frappe.sh` runs
**Then** a wheel cache directory is created at `/tmp/pip-wheel-cache`
**And** the gunicorn wheel is built from `git+https://github.com/frappe/gunicorn@bb554053bb...`
**And** `PIP_FIND_LINKS` is exported to point at the cache directory
**And** subsequent pip installs use the cached wheel instead of cloning

#### Scenario: Wheel cache reuse during app installation

**Given** the wheel cache has been populated with gunicorn wheel
**When** `pip install -e apps/frappe` runs
**Then** pip finds gunicorn in `PIP_FIND_LINKS` location
**And** no git clone operation occurs for gunicorn

#### Scenario: Setup script runs standalone

**Given** `setup_stack.sh` is run without `setup-frappe.sh` preceding it
**When** `PIP_FIND_LINKS` is not set in the environment
**Then** pip install operations proceed normally (fallback behavior)
**And** no errors occur due to missing cache

## MODIFIED Requirements

None.

## REMOVED Requirements

None.
