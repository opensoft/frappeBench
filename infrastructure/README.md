# Frappe Infrastructure Stack

This stack runs the shared infrastructure services for all Frappe workspaces:
- MariaDB
- Redis (cache/queue/socketio)

## Start/Stop

```bash
cd /home/brett/projects/workBenches/devBenches/frappeBench/infrastructure

docker compose up -d
# Stop
# docker compose down
```

## Notes
- Stack name: `frappe-infra`
- Containers are named `frappe-mariadb`, `frappe-redis-cache`, `frappe-redis-queue`, `frappe-redis-socketio`.
- The network is `frappe-network` and is shared with all workspace stacks.
