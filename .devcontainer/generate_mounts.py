#!/usr/bin/env python3
"""
Generate docker-compose.mounts.yml from frappe-apps.json (JSON with // comments).
This runs on the host via devcontainer initializeCommand, before compose starts.
"""

import json
import os
import re
from pathlib import Path

INPUT_FILE = Path(__file__).with_name("frappe-apps.json")
OUTPUT_FILE = Path(__file__).with_name("docker-compose.mounts.yml")
SERVICE_NAME = "frappe"  # must match service name in docker-compose.yml
DEFAULT_APP_BASE = "/workspace/development/frappe-bench/apps"


def parse_jsonc(path: Path):
    """Parse JSON, allowing // comments."""
    content = path.read_text()
    content_no_comments = re.sub(r"//.*", "", content)
    return json.loads(content_no_comments)


def describe_path(path: Path) -> str:
    """Return a short status string for a filesystem path."""
    parts = [
        f"exists={path.exists()}",
        f"is_dir={path.is_dir()}",
        f"is_file={path.is_file()}",
    ]
    try:
        parts.append(f"resolved={path.resolve()}")
    except OSError:
        parts.append("resolved=<unavailable>")
    return ", ".join(parts)


def list_dir(path: Path, limit: int = 20):
    """List directory entries (non-recursive) with a safety limit."""
    if not path.exists() or not path.is_dir():
        return "<not a directory>"
    try:
        entries = sorted(os.listdir(path))
    except OSError as exc:  # e.g., permission issues
        return f"<error listing: {exc}>"
    trimmed = entries[:limit]
    suffix = "" if len(entries) <= limit else f" ... (+{len(entries) - limit} more)"
    return "[" + ", ".join(trimmed) + "]" + suffix


def generate_compose():
    volumes = []
    if INPUT_FILE.exists():
        try:
            mounts = parse_jsonc(INPUT_FILE)
            if not isinstance(mounts, list):
                raise ValueError("frappe-apps.json must be a JSON array")
            for m in mounts:
                if not isinstance(m, dict):
                    continue
                src = m.get("source")
                tgt = m.get("target")
                if not tgt:
                    app_name = m.get("app")
                    if not app_name:
                        # Without target or app, we cannot safely derive a path.
                        continue
                    tgt = f"{DEFAULT_APP_BASE}/{app_name}"
                if src and tgt:
                    src_path = Path(src).expanduser()
                    print(f"[Mount] source={src_path}")
                    print(f"        source status: {describe_path(src_path)}")
                    print(f"        source entries: {list_dir(src_path)}")
                    print(f"        target (container): {tgt}")
                    tgt_path = Path(tgt)
                    print(
                        f"        target status (host path for reference only): {describe_path(tgt_path)}"
                    )
                    volumes.append(f"{src}:{tgt}")
        except Exception as exc:  # pylint: disable=broad-except
            print(f"[Error] Failed to parse {INPUT_FILE.name}: {exc}")
    else:
        print(f"[Info] {INPUT_FILE.name} not found. No dynamic mounts added.")

    with OUTPUT_FILE.open("w") as f:
        f.write(
            "# This file is generated from frappe-apps.json via generate_mounts.py\n"
        )
        f.write("version: '3.8'\n")
        f.write("services:\n")
        f.write(f"  {SERVICE_NAME}:\n")
        if volumes:
            f.write("    volumes:\n")
            for vol in volumes:
                f.write(f"      - {vol}\n")
        else:
            f.write("    environment:\n")
            f.write("      - DYNAMIC_MOUNTS_LOADED=false\n")

    print(f"[Success] Generated {OUTPUT_FILE.name} with {len(volumes)} mounts.")


if __name__ == "__main__":
    generate_compose()
