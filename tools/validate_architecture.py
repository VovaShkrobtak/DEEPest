#!/usr/bin/env python3
"""Small static boundary guard; intentional world -> physiology dependency only."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
# Explicitly declared same-model NPC reuse; all other sibling imports fail.
DOMAIN_IMPORT_ALLOWLIST = {("world.gd", "physiology.gd"), ("physiology.gd", "anatomy.gd"), ("zombies.gd", "infected_navigation.gd")}
BANNED = re.compile(r"\b(?:Node\w*|SceneTree|OS|FileAccess|DirAccess|Time)\b|(?<![.\w])(?:randf|randfn|randi|randf_range|randi_range|randomize|seed|rand_from_seed)\s*\(")
IMPORT = re.compile(r'\b(?:preload|load)\s*\(\s*[\"\']([^\"\']+)[\"\']\s*\)')


def code_only(text: str) -> str:
    # Strip comments without deleting # inside strings.
    lines = []
    for line in text.splitlines():
        quote = ""
        escaped = False
        cleaned = ""
        for char in line:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif quote:
                if char == quote:
                    quote = ""
            elif char in "\"'":
                quote = char
            elif char == "#":
                break
            cleaned += char
        lines.append(cleaned)
    return "\n".join(lines)


def main() -> int:
    failures = []
    for path in sorted((ROOT / "src/domain").glob("*.gd")):
        code = code_only(path.read_text())
        # Strings are excluded from forbidden-symbol matching, imports checked separately.
        symbols = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', '""', code)
        for match in BANNED.finditer(symbols):
            failures.append(f"{path.relative_to(ROOT)}: forbidden domain API {match.group()}")
        for dependency in IMPORT.findall(code):
            peer = Path(dependency).name
            if not dependency.startswith("res://src/domain/") or (path.name, peer) not in DOMAIN_IMPORT_ALLOWLIST:
                failures.append(f"{path.relative_to(ROOT)}: undeclared dependency {dependency}")
    for path in sorted((ROOT / "src/adapters").glob("*ui*.gd")):
        code = code_only(path.read_text())
        if re.search(r"\b(?:export_state|restore_state)\s*\(", code):
            failures.append(f"{path.relative_to(ROOT)}: UI must use snapshot/debug_snapshot and save adapter")
        if re.search(r"\bkernel\s*\.\s*_state\b", code):
            failures.append(f"{path.relative_to(ROOT)}: UI reads mutable kernel state")
    for failure in failures:
        print("FAIL", failure)
    if not failures:
        print("Architecture boundaries passed (world -> physiology explicitly allowed)")
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
