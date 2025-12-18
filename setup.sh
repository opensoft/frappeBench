#!/bin/bash
# Host setup script - run this on the host before starting the Dev Container
# This sets up Git worktrees that need to exist before the container mounts the workspace

set -euo pipefail

echo "Setting up Git worktrees on host..."
bash scripts/setup-worktrees.sh --prepare
echo "Worktree setup complete. You can now start the Dev Container."
