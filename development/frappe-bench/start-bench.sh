#!/bin/bash
# Auto-start bench server in the background

BENCH_DIR="/workspace/development/frappe-bench"
cd $BENCH_DIR

# Check if bench is already running
if pgrep -f "bench serve" > /dev/null; then
    echo "Bench server is already running"
    exit 0
fi

echo "Starting Frappe bench server..."
nohup bench start > /tmp/bench.log 2>&1 &
echo "Bench server started. Check logs at /tmp/bench.log"
