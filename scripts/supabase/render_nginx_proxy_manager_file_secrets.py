#!/usr/bin/env python3
"""Render a resolved NPM Compose config into a file-secret candidate."""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
from pathlib import Path
from typing import Any


APP_SERVICE = "nginx-proxy-manager-app"
DB_SERVICE = "nginx-proxy-manager-db"
APP_PASSWORD = "DB_MYSQL_PASSWORD"
APP_PASSWORD_FILE = "DB_MYSQL_PASSWORD__FILE"
DB_PASSWORD = "MYSQL_PASSWORD"
DB_PASSWORD_FILE = "MYSQL_PASSWORD_FILE"
DB_ROOT_PASSWORD = "MYSQL_ROOT_PASSWORD"
DB_ROOT_PASSWORD_FILE = "MYSQL_ROOT_PASSWORD_FILE"
APP_SECRET = "npm_db_password"
ROOT_SECRET = "npm_db_root_password"


class RenderError(Exception):
    """Expected input/contract error without credential detail."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("resolved_compose", type=Path)
    parser.add_argument("original_env", type=Path)
    parser.add_argument("candidate_compose", type=Path)
    parser.add_argument("candidate_env", type=Path)
    parser.add_argument("secrets_dir", type=Path)
    return parser.parse_args()


def require_mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise RenderError(f"{label} không phải mapping.")
    return value


def pop_password(environment: dict[str, Any], key: str) -> str:
    value = environment.pop(key, None)
    if not isinstance(value, str) or len(value) < 12:
        raise RenderError(f"{key} thiếu hoặc không đạt minimum length.")
    if any(character in value for character in ("\0", "\r", "\n")):
        raise RenderError(f"{key} không phải single-line credential.")
    return value


def secret_sources(service: dict[str, Any]) -> set[str]:
    configured = service.get("secrets", [])
    if not isinstance(configured, list):
        raise RenderError("Service secrets không phải list.")
    sources: set[str] = set()
    for item in configured:
        if isinstance(item, str):
            sources.add(item)
        elif isinstance(item, dict) and isinstance(item.get("source"), str):
            sources.add(item["source"])
        else:
            raise RenderError("Service secret entry không canonical.")
    return sources


def add_secret(service: dict[str, Any], name: str) -> None:
    configured = service.setdefault("secrets", [])
    if name not in secret_sources(service):
        configured.append({"source": name, "target": name})


def exclusive_write(path: Path, content: bytes, mode: int) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        os.write(descriptor, content)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.chmod(path, mode)


def filtered_env(original: str, forbidden_values: tuple[str, str]) -> str:
    forbidden_keys = {APP_PASSWORD, DB_PASSWORD, DB_ROOT_PASSWORD}
    kept: list[str] = []
    for line in original.splitlines(keepends=True):
        candidate = line.strip()
        key = candidate.split("=", 1)[0] if "=" in candidate else ""
        if key in forbidden_keys:
            continue
        kept.append(line)
    result = "".join(kept)
    if any(secret in result for secret in forbidden_values):
        raise RenderError("Candidate env còn chứa database credential.")
    return result


def render(args: argparse.Namespace) -> None:
    try:
        config = json.loads(args.resolved_compose.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise RenderError("Resolved Compose JSON không đọc được.") from error

    root = require_mapping(config, "Compose root")
    services = require_mapping(root.get("services"), "Compose services")
    app = require_mapping(services.get(APP_SERVICE), APP_SERVICE)
    database = require_mapping(services.get(DB_SERVICE), DB_SERVICE)
    app_environment = require_mapping(app.get("environment"), "App environment")
    db_environment = require_mapping(database.get("environment"), "DB environment")

    for environment, file_keys in (
        (app_environment, (APP_PASSWORD_FILE,)),
        (db_environment, (DB_PASSWORD_FILE, DB_ROOT_PASSWORD_FILE)),
    ):
        if any(key in environment for key in file_keys):
            raise RenderError("Compose đã có file-secret environment một phần.")

    app_password = pop_password(app_environment, APP_PASSWORD)
    db_password = pop_password(db_environment, DB_PASSWORD)
    root_password = pop_password(db_environment, DB_ROOT_PASSWORD)
    if app_password != db_password:
        raise RenderError("App và database user password không khớp.")

    app_environment[APP_PASSWORD_FILE] = f"/run/secrets/{APP_SECRET}"
    db_environment[DB_PASSWORD_FILE] = f"/run/secrets/{APP_SECRET}"
    db_environment[DB_ROOT_PASSWORD_FILE] = f"/run/secrets/{ROOT_SECRET}"

    top_secrets = root.setdefault("secrets", {})
    if not isinstance(top_secrets, dict):
        raise RenderError("Top-level secrets không phải mapping.")
    for name in (APP_SECRET, ROOT_SECRET):
        if name in top_secrets:
            raise RenderError("Compose secret target đã tồn tại.")
    top_secrets[APP_SECRET] = {"file": f"./secrets/{APP_SECRET}"}
    top_secrets[ROOT_SECRET] = {"file": f"./secrets/{ROOT_SECRET}"}
    add_secret(app, APP_SECRET)
    add_secret(database, APP_SECRET)
    add_secret(database, ROOT_SECRET)

    candidate_text = json.dumps(root, indent=2, sort_keys=True) + "\n"
    if app_password in candidate_text or root_password in candidate_text:
        raise RenderError("Candidate Compose còn chứa database credential.")

    try:
        env_text = args.original_env.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise RenderError("Production env không đọc được.") from error
    candidate_env = filtered_env(env_text, (app_password, root_password))

    if args.secrets_dir.exists():
        raise RenderError("Secrets output directory đã tồn tại.")
    args.secrets_dir.mkdir(mode=0o700, parents=False)
    os.chmod(args.secrets_dir, 0o700)

    exclusive_write(args.candidate_compose, candidate_text.encode(), 0o600)
    exclusive_write(args.candidate_env, candidate_env.encode(), 0o600)
    exclusive_write(args.secrets_dir / APP_SECRET, app_password.encode(), 0o400)
    exclusive_write(args.secrets_dir / ROOT_SECRET, root_password.encode(), 0o400)

    for path, expected in (
        (args.candidate_compose, 0o600),
        (args.candidate_env, 0o600),
        (args.secrets_dir, 0o700),
        (args.secrets_dir / APP_SECRET, 0o400),
        (args.secrets_dir / ROOT_SECRET, 0o400),
    ):
        if stat.S_IMODE(path.stat().st_mode) != expected:
            raise RenderError("Rendered file permission không đạt contract.")


def main() -> int:
    try:
        render(parse_args())
    except RenderError as error:
        print(f"NPM file-secret render fail: {error}", file=sys.stderr)
        return 1
    print("NPM file-secret candidate render pass.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
