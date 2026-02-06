#!/usr/bin/env python3
from pathlib import Path
import re


LOCK_PATH = Path("vibe-kanban/crates/remote/Cargo.lock")


def process_block(block_lines):
    if not block_lines:
        return []

    name = None
    for line in block_lines:
        m = re.match(r'\s*name\s*=\s*"([^"]+)"', line)
        if m:
            name = m.group(1)
            break

    if name == "billing":
        return []

    if name == "remote":
        filtered = []
        for line in block_lines:
            stripped = line.strip()
            if stripped == '"billing",' or stripped == '"billing"':
                continue
            filtered.append(line)
        return filtered

    return block_lines


def strip_billing_dependency(text: str) -> str:
    lines = text.splitlines(keepends=True)

    out = []
    block = []
    for line in lines:
        if line.strip() == "[[package]]":
            out.extend(process_block(block))
            block = [line]
        else:
            block.append(line)

    out.extend(process_block(block))
    return "".join(out)


def main() -> int:
    if not LOCK_PATH.exists():
        print(f"Cargo.lock not found at {LOCK_PATH}")
        return 1

    original = LOCK_PATH.read_text()
    updated = strip_billing_dependency(original)

    if updated == original:
        print("No billing entries found to strip.")
        return 0

    LOCK_PATH.write_text(updated)
    print("Stripped billing from Cargo.lock for OSS build.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
