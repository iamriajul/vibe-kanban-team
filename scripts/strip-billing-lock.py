#!/usr/bin/env python3
import re
from pathlib import Path


LOCK_PATH = Path("vibe-kanban/crates/remote/Cargo.lock")


def strip_billing_dependency(text: str) -> str:
    # Remove billing from the remote package dependencies list.
    def strip_from_remote(match: re.Match) -> str:
        block = match.group(0)
        block = block.replace(' "billing",\n', "")
        block = block.replace(' "billing"\n', "")
        return block

    text = re.sub(
        r"\[\[package\]\][\s\S]*?name = \"remote\"[\s\S]*?(?=\n\[\[package\]\]|\Z)",
        strip_from_remote,
        text,
        count=1,
    )

    # Remove the billing package block entirely.
    parts = text.split("[[package]]")
    if len(parts) == 1:
        return text

    out = [parts[0]]
    for block in parts[1:]:
        if re.search(r"\nname = \"billing\"\n", block):
            continue
        out.append("[[package]]" + block)

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
