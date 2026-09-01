#!/usr/bin/env python3
"""Bounded, no-follow store for ~/.config/omarchy/todo-list/items.json."""

from __future__ import annotations

import json
import os
import secrets
import stat
import sys

MAX_BYTES = 256 * 1024
MAX_ITEMS = 200
MAX_HISTORY = 100
MAX_TEXT = 500
MAX_ID = 64
EMPTY = {"version": 1, "items": [], "history": []}


def die(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def clip_text(value: object) -> str:
    text = str(value or "").replace("\x00", "").strip()
    if len(text) > MAX_TEXT:
        return text[:MAX_TEXT]
    return text


def clip_id(value: object) -> str:
    text = str(value or "").replace("\x00", "")
    if len(text) > MAX_ID:
        return text[:MAX_ID]
    return text


def clip_time(value: object) -> int:
    try:
        number = int(str(value))
    except (TypeError, ValueError):
        return 0
    if number < 0 or number > 4102444800000:
        return 0
    return number


def normalize_item(item: object, fallback_done: bool) -> dict | None:
    if not isinstance(item, dict):
        return None
    text = clip_text(item.get("text"))
    if not text:
        return None
    ident = clip_id(item.get("id"))
    if not ident:
        return None
    reason = "dismissed" if item.get("reason") == "dismissed" else "completed"
    return {
        "id": ident,
        "text": text,
        "done": item.get("done") is True or fallback_done,
        "createdAt": clip_time(item.get("createdAt")),
        "completedAt": clip_time(item.get("completedAt")),
        "reason": reason,
    }


def sanitize(doc: object) -> dict:
    source: list[object] = []
    hist_source: list[object] = []
    if isinstance(doc, list):
        source = doc
    elif isinstance(doc, dict):
        items_raw = doc.get("items")
        hist_raw = doc.get("history")
        if isinstance(items_raw, list):
            source = items_raw
        if isinstance(hist_raw, list):
            hist_source = hist_raw

    items: list[dict] = []
    history: list[dict] = []
    seen: set[str] = set()

    def take(raw: object, done: bool, bucket: list[dict], cap: int) -> None:
        if len(bucket) >= cap:
            return
        item = normalize_item(raw, done)
        if not item or item["id"] in seen:
            return
        seen.add(item["id"])
        bucket.append(item)

    for raw in source:
        item = normalize_item(raw, False)
        if not item:
            continue
        if item["done"]:
            take(item, True, history, MAX_HISTORY)
        else:
            take(item, False, items, MAX_ITEMS)

    for raw in hist_source:
        take(raw, True, history, MAX_HISTORY)

    return {"version": 1, "items": items, "history": history}


def ensure_dir(path: str) -> None:
    os.makedirs(path, mode=0o700, exist_ok=True)
    info = os.lstat(path)
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        die("store dir is not a directory")
    if info.st_uid != os.getuid():
        die("store dir owner mismatch")
    os.chmod(path, 0o700)


def open_nofollow(path: str, flags: int, mode: int = 0o600) -> tuple[int, os.stat_result]:
    fd = os.open(path, flags | os.O_NOFOLLOW | os.O_CLOEXEC, mode)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            os.close(fd)
            die("store is not a regular file")
        if info.st_uid != os.getuid():
            os.close(fd)
            die("store owner mismatch")
        return fd, info
    except Exception:
        os.close(fd)
        raise


def load(dirpath: str) -> None:
    ensure_dir(dirpath)
    path = os.path.join(dirpath, "items.json")
    try:
        fd, _info = open_nofollow(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        payload = (json.dumps(EMPTY, indent=2) + "\n").encode()
        os.write(fd, payload)
        os.fsync(fd)
        os.close(fd)
        os.chmod(path, 0o600)
        sys.stdout.write(json.dumps(EMPTY, indent=2) + "\n")
        return
    except FileExistsError:
        pass
    except OSError as error:
        die(f"create failed: {error}")

    try:
        fd, info = open_nofollow(path, os.O_RDONLY)
    except OSError as error:
        die(f"open failed: {error}")
        return
    if info.st_size > MAX_BYTES:
        os.close(fd)
        die("store too large")
    data = os.read(fd, MAX_BYTES + 1)
    os.close(fd)
    if len(data) > MAX_BYTES:
        die("store too large")
    try:
        doc = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        doc = EMPTY
    sys.stdout.write(json.dumps(sanitize(doc), indent=2) + "\n")


def save(dirpath: str) -> None:
    ensure_dir(dirpath)
    raw = sys.stdin.buffer.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        die("payload too large")
    try:
        doc = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        die("invalid json")
        return
    out = (json.dumps(sanitize(doc), indent=2) + "\n").encode()
    if len(out) > MAX_BYTES:
        die("payload too large")
    path = os.path.join(dirpath, "items.json")
    tmp = os.path.join(dirpath, ".items." + secrets.token_hex(12) + ".tmp")
    try:
        fd, _info = open_nofollow(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.write(fd, out)
        os.fsync(fd)
        os.close(fd)
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] not in ("load", "save"):
        die("usage: store.py load|save DIR")
    action, dirpath = sys.argv[1], sys.argv[2]
    if not dirpath or "\x00" in dirpath:
        die("invalid dir")
    if action == "load":
        load(dirpath)
    else:
        save(dirpath)


if __name__ == "__main__":
    main()
