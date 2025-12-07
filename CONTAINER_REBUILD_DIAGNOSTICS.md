# Container Rebuild Diagnostics Guide

## Overview

This document provides a structured diagnostic framework for troubleshooting Frappe development container rebuild issues. It is designed to be machine-readable by AI assistants to systematically identify and resolve problems during the container initialization process.

## Diagnostic Structure

Each diagnostic section follows this format:

- **Check ID**: Unique identifier for the check
- **Description**: What the check verifies
- **Command**: How to perform the check
- **Expected Result**: What should happen if everything is working
- **Failure Symptoms**: What indicates a problem
- **Resolution Steps**: How to fix the issue
- **Priority**: Critical/High/Medium/Low

## Pre-Rebuild Checks

### CHECK-001: Host Environment Validation

**Description**: Verify that the host system has all required dependencies and configurations before starting container rebuild.

**Command**:

```bash
# Check Docker version
docker --version

# Check Docker Compose version
docker compose version

# Check available disk space
df -h /workspace

# Check Git configuration
git config --list --show-origin

# Check environment variables
echo "USER: $USER"
echo "UID: $UID"
echo "GID: $GID"
echo "PROJECT_NAME: ${PROJECT_NAME:-frappe}"
echo "DB_PASSWORD: ${DB_PASSWORD:-frappe}"
```

**Expected Result**:

- Docker version >= 20.10
- Docker Compose version >= 2.0
- At least 10GB free disk space
- Git user.name and user.email configured
- Environment variables set appropriately

**Failure Symptoms**:

- Container build fails immediately
- Permission errors during volume mounting

**Resolution Steps**:

1. Install/update Docker and Docker Compose
2. Ensure sufficient disk space
3. Configure Git user settings
4. Set required environment variables in .env file

**Priority**: Critical

### CHECK-002: Configuration File Validation

**Description**: Validate that all configuration files are present and syntactically correct.

**Command**:

```bash
# Check required files exist
ls -la .devcontainer/
ls -la frappe-apps.json
ls -la frappe-apps.example.json

# Validate JSON syntax
python3 -m json.tool frappe-apps.json > /dev/null && echo "JSON valid" || echo "JSON invalid"

# Check devcontainer configuration
cat .devcontainer/devcontainer.json | python3 -c "import sys, json; json.load(sys.stdin); print('devcontainer.json valid')"
```

**Expected Result**:

- All required files present
- JSON files parse without errors
- devcontainer.json is valid JSON

**Failure Symptoms**:

- Scripts fail with "file not found" errors
- JSON parsing errors in logs

**Resolution Steps**:

1. Copy frappe-apps.example.json to frappe-apps.json
2. Validate JSON syntax with online validator or python3 -m json.tool
3. Ensure devcontainer.json follows VS Code devcontainer specification

**Priority**: Critical

## Build-Time Diagnostics

### CHECK-003: Docker Compose Service Health

**Description**: Verify that all dependent services start correctly during container build.

**Command**:

```bash
# Check service health during build
docker compose ps

# Check MariaDB connectivity
docker compose exec mariadb mysqladmin ping -h localhost -u root -p${DB_PASSWORD:-frappe}

# Check Redis instances
docker compose exec redis-cache redis-cli ping
docker compose exec redis-queue redis-cli ping
docker compose exec redis-socketio redis-cli ping
```

**Expected Result**:

- All services show "Up" status
- MariaDB ping returns "pong"
- Redis pings return "PONG"

**Failure Symptoms**:

- Container build hangs waiting for services
- Database connection errors in logs
- Redis connection failures

**Resolution Steps**:

1. Check service logs: `docker compose logs <service-name>`
2. Verify service dependencies in docker-compose.yml
3. Check resource limits and adjust if needed
4. Restart services: `docker compose restart <service-name>`

**Priority**: Critical

### CHECK-004: Worktree Setup Validation

**Description**: Verify that git worktrees are created correctly during initializeCommand phase.

**Command**:

```bash
# Check worktree script execution
/workspace/.devcontainer/setup-worktrees.sh

# Verify worktrees exist
ls -la /workspace
git worktree list

# Check worktree branches
for worktree in $(git worktree list --porcelain | grep worktree | awk '{print $2}'); do
  echo "Worktree: $worktree"
  cd "$worktree" && git branch --show-current && cd /workspace
done
```

**Expected Result**:

- setup-worktrees.sh exits with code 0
- Worktrees exist in expected locations
- Each worktree is on correct branch

**Failure Symptoms**:

- "worktree already exists" errors
- Missing worktree directories
- Incorrect branch checkouts

**Resolution Steps**:

1. Remove conflicting worktrees: `git worktree remove <path>`
2. Check frappe-apps.json worktree configuration
3. Verify branch names exist in remote repository
4. Clean up .git/worktrees directory if corrupted

**Priority**: High

## Post-Build Diagnostics

### CHECK-005: Bench Environment Validation

**Description**: Verify that Frappe bench is properly initialized and configured.

**Command**:

```bash
# Check bench installation
which bench
bench --version

# Check bench configuration
bench config

# Verify Python environment
python3 --version
which python3
pip list | grep frappe

# Check site directories
ls -la /workspace/development/frappe-bench/sites/
```

**Expected Result**:

- bench command available
- Python 3.10 environment active
- frappe package installed
- sites directory exists

**Failure Symptoms**:

- "bench command not found" errors
- Python import errors
- Missing site configurations

**Resolution Steps**:

1. Reinstall bench: `pip install frappe-bench`
2. Recreate virtual environment if corrupted
3. Check PATH environment variable
4. Verify site configuration in frappe-apps.json

**Priority**: Critical

### CHECK-006: Site and App Installation

**Description**: Verify that sites and apps are created and installed correctly.

**Command**:

```bash
# Run site setup script
/workspace/.devcontainer/setup-apps.sh

# Check sites exist
bench list-sites

# Check apps installed
bench list-apps

# Verify site configuration
for site in $(bench list-sites); do
  echo "Site: $site"
  bench --site "$site" show-config
done
```

**Expected Result**:

- setup-apps.sh exits successfully
- Sites listed match frappe-apps.json
- Apps installed and linked to sites

**Failure Symptoms**:

- Site creation fails
- App installation errors
- Database connection issues

**Resolution Steps**:

1. Check MariaDB service status
2. Verify site configuration in frappe-apps.json
3. Check app repository URLs and branches
4. Clean up failed sites: `bench drop-site <site-name>`

**Priority**: High

### CHECK-007: Network and Service Connectivity

**Description**: Verify that all services can communicate with each other.

**Command**:

```bash
# Test database connectivity from frappe container
docker compose exec frappe mysql -h mariadb -u frappe -p${DB_PASSWORD:-frappe} -e "SELECT 1"

# Test Redis connectivity
docker compose exec frappe redis-cli -h redis-cache ping
docker compose exec frappe redis-cli -h redis-queue ping
docker compose exec frappe redis-cli -h redis-socketio ping

# Check port availability
netstat -tlnp | grep -E ':(8000|9000|6379|3306)'

# Test bench start (briefly)
timeout 10 bench start || echo "Bench start test completed"
```

**Expected Result**:

- Database queries succeed
- Redis connections return PONG
- Required ports are listening
- Bench start initiates without immediate errors

**Failure Symptoms**:

- Connection refused errors
- Port binding conflicts
- Service discovery failures

**Resolution Steps**:

1. Check service logs for connection errors
2. Verify network configuration in docker-compose.yml
3. Check firewall settings
4. Restart affected services

**Priority**: High

### CHECK-008: File Permissions and Ownership

**Description**: Verify that file permissions allow proper operation.

**Command**:

```bash
# Check ownership of workspace
ls -la /workspace

# Check frappe-bench permissions
ls -la /workspace/development/frappe-bench/

# Check site file permissions
find /workspace/development/frappe-bench/sites/ -type f -exec ls -l {} \; | head -20

# Check user ID consistency
id
echo "Container user: $(whoami)"
echo "Host user: $USER"
echo "UID: $UID, GID: $GID"
```

**Expected Result**:

- Files owned by correct user
- Executable permissions on scripts
- Read/write access to necessary directories

**Failure Symptoms**:

- Permission denied errors
- File access failures
- Ownership mismatches

**Resolution Steps**:

1. Fix ownership: `chown -R $UID:$GID /workspace`
2. Set correct permissions: `chmod +x /workspace/.devcontainer/*.sh`
3. Check docker-compose.yml user configuration
4. Verify volume mount permissions

**Priority**: Medium

## Log Analysis

### CHECK-009: Container Build Logs

**Description**: Analyze container build logs for errors and warnings.

**Command**:

```bash
# Get build logs
docker compose logs --tail=100 frappe

# Check for specific error patterns
docker compose logs frappe 2>&1 | grep -i error
docker compose logs frappe 2>&1 | grep -i fail
docker compose logs frappe 2>&1 | grep -i exception

# Check initializeCommand logs
docker compose logs frappe 2>&1 | grep -A 10 -B 5 "setup-worktrees"

# Check postCreateCommand logs
docker compose logs frappe 2>&1 | grep -A 10 -B 5 "setup-apps"
```

**Expected Result**:

- No critical errors in logs
- Scripts execute successfully
- Services start without issues

**Failure Symptoms**:

- Build failures
- Script execution errors
- Service startup failures

**Resolution Steps**:

1. Review full logs: `docker compose logs frappe > build.log`
2. Search for specific error messages
3. Check timestamps to correlate events
4. Compare with successful build logs

**Priority**: High

### CHECK-010: System Resource Usage

**Description**: Check system resources during and after build.

**Command**:

```bash
# Check memory usage
docker stats --no-stream

# Check disk usage
df -h
du -sh /workspace

# Check running processes
ps aux | grep -E "(frappe|bench|redis|mysql)"

# Check container resource limits
docker compose exec frappe cat /proc/meminfo | head -5
```

**Expected Result**:

- Memory usage within limits
- Sufficient disk space
- Processes running normally
- No resource exhaustion

**Failure Symptoms**:

- Out of memory errors
- Disk full errors
- Process crashes
- Slow performance

**Resolution Steps**:

1. Increase resource limits in docker-compose.yml
2. Clean up disk space
3. Monitor resource usage during build
4. Optimize container configuration

**Priority**: Medium

## Automated Diagnostic Script

### CHECK-011: Run Comprehensive Diagnostics

**Description**: Execute automated diagnostic script to check all systems.

**Command**:

```bash
# Create and run diagnostic script
cat > /tmp/container-diagnostics.sh << 'EOF'
#!/bin/bash
set -e

echo "=== Container Rebuild Diagnostics ==="
echo "Timestamp: $(date)"
echo "Host: $(hostname)"
echo ""

# CHECK-001: Host Environment
echo "CHECK-001: Host Environment Validation"
docker --version || echo "FAIL: Docker not found"
docker compose version || echo "FAIL: Docker Compose not found"
df -h /workspace | tail -1 | awk '{if($4+0 < 10) print "FAIL: Low disk space"}' || echo "PASS: Disk space OK"
echo ""

# CHECK-002: Configuration Files
echo "CHECK-002: Configuration File Validation"
[ -f ".devcontainer/devcontainer.json" ] && echo "PASS: devcontainer.json exists" || echo "FAIL: devcontainer.json missing"
[ -f "frappe-apps.json" ] && echo "PASS: frappe-apps.json exists" || echo "FAIL: frappe-apps.json missing"
python3 -m json.tool frappe-apps.json > /dev/null 2>&1 && echo "PASS: frappe-apps.json valid JSON" || echo "FAIL: frappe-apps.json invalid JSON"
echo ""

# CHECK-003: Service Health
echo "CHECK-003: Docker Compose Service Health"
docker compose ps --format json | jq -r '.[] | select(.State != "running") | "FAIL: Service \(.Name) not running"' || echo "PASS: All services running"
echo ""

# CHECK-004: Worktrees
echo "CHECK-004: Worktree Setup"
git worktree list | wc -l | xargs -I {} echo "Found {} worktrees"
echo ""

# CHECK-005: Bench Environment
echo "CHECK-005: Bench Environment"
which bench > /dev/null 2>&1 && echo "PASS: bench command available" || echo "FAIL: bench command not found"
bench list-sites > /dev/null 2>&1 && echo "PASS: bench operational" || echo "FAIL: bench not operational"
echo ""

echo "=== Diagnostics Complete ==="
EOF

chmod +x /tmp/container-diagnostics.sh
/tmp/container-diagnostics.sh
```

**Expected Result**:

- Script runs without errors
- All checks show PASS or expected values
- Clear summary of system status

**Failure Symptoms**:

- Script execution fails
- Multiple FAIL messages
- Missing dependencies

**Resolution Steps**:

1. Fix any FAIL items shown in output
2. Re-run script to verify fixes
3. Save output for troubleshooting reference

**Priority**: High

## Common Issues and Solutions

### Issue: YAML Parsing Errors

**Symptoms**: "yaml: line X: mapping values are not allowed" during setup
**Cause**: YAML dependency in scripts, complex string handling
**Solution**: Use JSON-only configuration, temp file parsing

### Issue: Extension Installation Conflicts (ENOTEMPTY errors)

**Symptoms**: "ENOTEMPTY: directory not empty" errors during extension installation, extensions like GitHub Copilot fail to install initially but succeed later.

**Cause**: Leftover temporary directories from failed previous installations, race conditions during parallel extension installation.

**Resolution Steps**:

1. Run the extension troubleshooter: `bash .devcontainer/troubleshoot-extensions.sh`
2. Clean leftover temp directories: `rm -rf ~/.vscode-server/extensions/.*`
3. Rebuild container if issues persist: `Ctrl+Shift+P → "Dev Containers: Rebuild Container"`
4. Check VS Code extension logs for detailed error information

**Prevention**: The devcontainer.json now includes automatic cleanup of temp directories during initialization and post-create phases.

### Issue: Missing Extension Resource Files

**Symptoms**: "File not found" warnings for extension resources like logo files (e.g., claude-logo.svg)

**Cause**: Extension packaging issues, incomplete downloads, or upstream extension problems.

**Resolution Steps**:

1. This is typically a temporary issue that resolves with extension updates
2. Try reinstalling the specific extension: `Ctrl+Shift+P → "Extensions: Install Specific Version"`
3. Check the extension marketplace for known issues
4. The warning is cosmetic and doesn't affect functionality

**Prevention**: Keep extensions updated to latest versions to avoid packaging issues.

### Issue: Worktree Conflicts

**Symptoms**: "fatal: '/path' is already a working tree"
**Cause**: Previous worktree not cleaned up, concurrent builds
**Solution**: Remove existing worktrees, check frappe-apps.json for duplicates

### Issue: Database Connection Failures

**Symptoms**: "Can't connect to MySQL server"
**Cause**: MariaDB not ready, wrong credentials, network issues
**Solution**: Wait for health checks, verify DB_PASSWORD, check service logs

### Issue: Permission Errors

**Symptoms**: "Permission denied" on file operations
**Cause**: UID/GID mismatch between host and container
**Solution**: Ensure consistent user IDs, fix ownership with chown

### Issue: Out of Memory

**Symptoms**: Container killed, "Cannot allocate memory"
**Cause**: Insufficient memory limits, resource intensive operations
**Solution**: Increase CONTAINER_MEMORY in docker-compose.yml

## Emergency Recovery

### Full Reset Procedure

```bash
# Stop all services
docker compose down -v

# Clean up worktrees
git worktree list | awk '{print $1}' | xargs -I {} git worktree remove {} 2>/dev/null || true

# Remove containers and volumes
docker compose down -v --remove-orphans

# Clean up images (optional)
docker system prune -f

# Rebuild from scratch
docker compose up --build -d
```

### Quick Fix Commands

```bash
# Fix common permission issues
docker compose exec frappe chown -R $UID:$GID /workspace

# Restart services
docker compose restart

# Re-run setup scripts
docker compose exec frappe /workspace/.devcontainer/setup-worktrees.sh
docker compose exec frappe /workspace/.devcontainer/setup-apps.sh
```

## Configuration Reference

### frappe-apps.json Structure

```json
{
  "worktrees": [
    {
      "name": "frappe-app-dartwing",
      "url": "https://github.com/opensoft/frappe-app-dartwing.git",
      "branch": "develop",
      "path": "development/frappe-bench/apps/frappe-app-dartwing"
    }
  ],
  "sites": [
    {
      "name": "dev.dartwing.localhost",
      "apps": ["frappe", "frappe-app-dartwing"],
      "db_name": "dev_dartwing",
      "admin_password": "admin"
    }
  ]
}
```

### Environment Variables

- `PROJECT_NAME`: Container naming prefix (default: frappe)
- `DB_PASSWORD`: MariaDB root password (default: frappe)
- `USER`: Host username for file ownership
- `UID`: Host user ID for container user
- `GID`: Host group ID for container user
- `CONTAINER_MEMORY`: Memory limit per container (default: 4g)
- `CONTAINER_CPUS`: CPU limit per container (default: 2)

This diagnostic guide should be updated whenever new issues are discovered or configurations change.
