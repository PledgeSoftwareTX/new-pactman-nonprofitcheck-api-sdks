"""
Access to the bundled fixture API.

Some scenarios cannot be summoned on demand from the production API: a revoked
exemption, an OFAC match, a cross-source conflict, an HTTP 429, a response
carrying a field newer than this SDK. Examples that need one of those run
against the fixture server in ``scripts/mock_server.py``, which speaks the same
envelope, error and check-count semantics as the real service.

Set ``PACTMAN_BASE_URL`` to point these examples somewhere else instead.
"""

from __future__ import annotations

import os
import sys
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from pactman_nonprofit_check_plus import PactmanClient

from .client import require_api_key

# The scripts/ directory is not an installable package; add it to the path so
# the fixture server and its records can be imported from here.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

from fixtures import CONTROL_EINS, FIXTURE_EINS, KNOWN_NONPROFIT_FIELDS
from mock_server import base_url_for, start_mock_server

__all__ = [
    "CONTROL_EINS",
    "FIXTURE_EINS",
    "KNOWN_NONPROFIT_FIELDS",
    "fixture_api",
]


@contextmanager
def fixture_api(**overrides: Any) -> Iterator[PactmanClient]:
    """
    Yields a client pointed at the fixture API.

    The server is started only when ``PACTMAN_BASE_URL`` is unset, and is always
    closed afterwards, so the example leaves no background work behind.
    """
    api_key = require_api_key()
    external = os.environ.get("PACTMAN_BASE_URL")
    server = None if external else start_mock_server(api_key=api_key)

    if server is None:
        base_url = external
    else:
        base_url = base_url_for(server)
        print(f"Using the bundled fixture API at {base_url} — these scenarios need")
        print("records and responses a live API will not produce on request.")

    options: dict[str, Any] = {"base_url": base_url, "timeout": 15.0}
    options.update(overrides)

    client = PactmanClient(api_key=api_key, **options)

    try:
        yield client
    finally:
        client.close()

        if server is not None:
            server.shutdown()
