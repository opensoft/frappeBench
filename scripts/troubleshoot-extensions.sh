#!/bin/bash
# Extension Installation Troubleshooting Script
# This script helps diagnose and fix extension installation issues

set -e

echo "=== Extension Installation Diagnostics ==="

# Check for leftover temp directories
echo "Checking for leftover extension temp directories..."
TEMP_DIRS=$(find /home/${USER}/.vscode-server/extensions/ -name ".*" -type d 2>/dev/null | wc -l)
if [ "$TEMP_DIRS" -gt 0 ]; then
    echo "Found $TEMP_DIRS leftover temp directories. Cleaning up..."
    find /home/${USER}/.vscode-server/extensions/ -name ".*" -type d -exec rm -rf {} + 2>/dev/null || true
    echo "Cleanup completed."
else
    echo "No leftover temp directories found."
fi

# Check extension installation status
echo -e "\nChecking installed extensions..."
INSTALLED_EXTENSIONS=$(ls -1 /home/${USER}/.vscode-server/extensions/ | grep -v "^\." | wc -l)
echo "Found $INSTALLED_EXTENSIONS installed extensions"

# Check for common problematic extensions
echo -e "\nChecking for known problematic extensions..."
PROBLEMATIC_EXTENSIONS=(
    "github.copilot"
    "github.copilot-chat"
    "anthropic.claude-code"
)

for ext in "${PROBLEMATIC_EXTENSIONS[@]}"; do
    if [ -d "/home/${USER}/.vscode-server/extensions/${ext}"* ]; then
        echo "✓ $ext appears to be installed"
    else
        echo "✗ $ext may not be properly installed"
    fi
done

# Check disk space
echo -e "\nChecking disk space..."
df -h /home/${USER}/.vscode-server/extensions/

echo -e "\n=== Diagnostics Complete ==="
echo "If issues persist, try:"
echo "1. Rebuild the container: Ctrl+Shift+P → 'Dev Containers: Rebuild Container'"
echo "2. Clear extension cache: rm -rf /home/${USER}/.vscode-server/extensions/.*"
echo "3. Check VS Code logs for detailed error messages"