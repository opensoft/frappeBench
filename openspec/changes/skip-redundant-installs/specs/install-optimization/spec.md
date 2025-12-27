# Spec Delta: Install Optimization - Skip Redundant Installs

## ADDED Requirements

### Requirement: Editable install detection

The setup scripts SHALL check if an app is already installed in editable mode before running `pip install -e`, skipping the installation if already present.

#### Scenario: App already installed in editable mode

**Given** an app "dartwing" is installed in editable mode at `/workspace/bench/apps/dartwing`
**When** `ensure_app_python_install "dartwing"` is called
**Then** the function detects the existing editable installation
**And** skips the `pip install -e` command
**And** logs "dartwing already installed, skipping"

#### Scenario: App not yet installed

**Given** an app "dartwing" directory exists but is not pip-installed
**When** `ensure_app_python_install "dartwing"` is called
**Then** `pip install -e apps/dartwing` executes
**And** the app becomes available in the Python environment

#### Scenario: App installed but not in editable mode

**Given** an app "dartwing" is installed via `pip install dartwing` (non-editable)
**When** `ensure_app_python_install "dartwing"` is called
**Then** `pip install -e apps/dartwing` executes to convert to editable mode
**And** the editable installation takes precedence

### Requirement: Idempotent setup execution

Running setup scripts multiple times SHALL produce the same result as running once, without redundant pip operations.

#### Scenario: Second run of setup_stack.sh

**Given** `setup_stack.sh` has already completed successfully
**When** `setup_stack.sh` is run again
**Then** all apps show "already installed, skipping"
**And** no pip install commands execute
**And** the script completes successfully

## MODIFIED Requirements

None.

## REMOVED Requirements

None.
