"""
Runs every documented example against the mock server.

This is what keeps the README honest: an example that stops importing, or stops
matching the SDK's surface, fails CI here rather than in a user's project.

    python scripts/run_examples_against_mock.py              # all, pass/fail only
    EXAMPLES_VERBOSE=1 python scripts/run_examples_against_mock.py
    python scripts/run_examples_against_mock.py ex_22 ex_23  # a subset
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from mock_server import base_url_for, start_mock_server

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "examples"
MOCK_API_KEY = "mock-key"
PER_EXAMPLE_TIMEOUT_SECONDS = 120


def select(patterns: list[str]) -> list[Path]:
    scripts = sorted(path for path in EXAMPLES.glob("*.py") if not path.name.startswith("_"))

    if not patterns:
        return scripts

    return [path for path in scripts if any(pattern in path.name for pattern in patterns)]


def main() -> int:
    verbose = bool(os.environ.get("EXAMPLES_VERBOSE"))
    scripts = select(sys.argv[1:])

    if not scripts:
        print("No examples matched.", file=sys.stderr)
        return 1

    server = start_mock_server(port=0, api_key=MOCK_API_KEY)
    base_url = base_url_for(server)
    print(f"Mock Pactman API on {base_url}\n")

    environment = {
        **os.environ,
        "PACTMAN_API_KEY": MOCK_API_KEY,
        "PACTMAN_BASE_URL": base_url,
        "PYTHONPATH": str(ROOT / "src"),
    }

    failures: list[str] = []

    try:
        for script in scripts:
            completed = subprocess.run(
                [sys.executable, str(script)],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=PER_EXAMPLE_TIMEOUT_SECONDS,
            )

            failed = completed.returncode != 0
            status = "FAIL" if failed else "ok"
            print(f"── {script.name}  [{status}]")

            if failed:
                failures.append(script.name)

            # Output is shown when asked for, and always when something failed —
            # a bare "FAIL" is not a diagnosis.
            if verbose or failed:
                for line in completed.stdout.splitlines():
                    print(f"   {line}")

                for line in completed.stderr.splitlines():
                    print(f"   ! {line}")

                print()
    finally:
        server.shutdown()

    print()

    if failures:
        print(f"{len(failures)} example(s) failed: {', '.join(failures)}", file=sys.stderr)
        return 1

    print(f"All {len(scripts)} examples ran clean.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
