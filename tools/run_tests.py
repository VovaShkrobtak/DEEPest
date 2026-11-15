#!/usr/bin/env python3
"""Run every standalone Godot test; reject runtime diagnostics even on exit 0."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    godot = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    if not godot:
        print("FAIL: Godot 4.6.3 executable missing", file=sys.stderr)
        return 1
    tests = sorted((ROOT / "tests").glob("test_*.gd"))
    if not tests:
        print("FAIL: no tests discovered", file=sys.stderr)
        return 1
    failed = 0
    with tempfile.TemporaryDirectory(prefix="deepest-tests-") as temporary:
        env = os.environ.copy()
        for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            folder = Path(temporary) / key.lower()
            folder.mkdir()
            env[key] = str(folder)
        version = subprocess.run([godot, "--version"], text=True, capture_output=True, env=env, timeout=30)
        if version.returncode or not version.stdout.strip().startswith("4.6.3."):
            print(f"FAIL: expected Godot 4.6.3, got {version.stdout.strip()!r}")
            return 1
        checks = [("architecture", [sys.executable, str(ROOT / "tools/validate_architecture.py")])]
        checks.append(("headless import", [godot, "--headless", "--editor", "--path", str(ROOT), "--import", "--quit"]))
        checks.extend((test.name, [godot, "--headless", "--path", str(ROOT), "--script", str(test)]) for test in tests)
        for label, command in checks:
            try:
                result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True, timeout=30)
                output = result.stdout + result.stderr
                bad = result.returncode != 0 or "SCRIPT ERROR" in output or "ERROR:" in output
            except subprocess.TimeoutExpired as error:
                captured_out = error.stdout.decode(errors="replace") if isinstance(error.stdout, bytes) else (error.stdout or "")
                captured_err = error.stderr.decode(errors="replace") if isinstance(error.stderr, bytes) else (error.stderr or "")
                output = f"Timed out after 30s: {error}\n{captured_out}\n{captured_err}"
                bad = True
            except OSError as error:
                output = str(error)
                bad = True
            print(f"{'FAIL' if bad else 'PASS'} {label}", flush=True)
            if bad:
                failed += 1
                print(output.strip(), flush=True)
    print(f"{len(checks) - failed}/{len(checks)} checks passed")
    return int(failed > 0)


if __name__ == "__main__":
    raise SystemExit(main())
