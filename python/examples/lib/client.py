"""
Client bootstrap shared by the numbered examples.

This is the pattern from ``ex_01_secure_client_init.py``, factored out so the
other examples can stay on their own subject. Nothing here is part of the SDK.
"""

from __future__ import annotations

import os
import sys
from typing import Any

from pactman_nonprofit_check_plus import PactmanClient


def require_api_key() -> str:
    """
    Reads the key from the environment, or exits with an explanation.

    The key is never printed, embedded in a message, or written to a file.
    """
    api_key = os.environ.get("PACTMAN_API_KEY")

    if not api_key:
        print("Set PACTMAN_API_KEY before running this example.", file=sys.stderr)
        raise SystemExit(1)

    return api_key


def create_client(**overrides: Any) -> PactmanClient:
    """
    A reusable client, pointed at production unless ``PACTMAN_BASE_URL``
    overrides it.

    Build one per process and share it — each instance carries its own throttle
    state and connection pool.
    """
    options: dict[str, Any] = {
        "base_url": os.environ.get("PACTMAN_BASE_URL"),
        "timeout": 15.0,
    }
    options.update(overrides)

    return PactmanClient(api_key=require_api_key(), **options)
