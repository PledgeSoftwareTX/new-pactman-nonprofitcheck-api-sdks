"""
A stand-in for the Nonprofit Check Plus API, so the examples can be run in CI
without a real key or network access.

Only the two check endpoints are implemented, with the same envelope shape, auth
header, batch limit, bulk matching semantics and cumulative check count as the
real service. Records come from ``fixtures.py``.

Run standalone:  python scripts/mock_server.py --port 8787
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import string
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from fixtures import CONTROL_EINS, FIXTURE_EINS, fixture_organization, has_fixture

MAX_BULK_EINS = 50
SINGLE_PATH = re.compile(r"^/api/entities/nonprofitcheck/v1/us/ein/(\d{9})$")
BULK_PATH = "/api/entities/nonprofitcheckbulk/v1/us/eins"

SLOW_RESPONSE_SECONDS = 5.0
"""How long the `slow` control EIN holds a response open."""

TRANSIENT_FAILURES = 2
"""How many times the `transient_failure` control EIN fails before succeeding."""


class _State:
    """Mirrors the real service: a running total for the billing cycle."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.checks_used_this_cycle = 0
        self._transient_failures_left = TRANSIENT_FAILURES

    def consume(self, count: int) -> int:
        with self._lock:
            self.checks_used_this_cycle += count
            return self.checks_used_this_cycle

    def refund(self, count: int) -> int:
        with self._lock:
            self.checks_used_this_cycle -= count
            return self.checks_used_this_cycle

    def take_transient_failure(self) -> bool:
        """True while failures remain; resets the budget once it is exhausted."""
        with self._lock:
            if self._transient_failures_left > 0:
                self._transient_failures_left -= 1
                return True

            self._transient_failures_left = TRANSIENT_FAILURES
            return False


def envelope(data: Any, errors: Any, check_count: int) -> dict[str, Any]:
    """The success envelope. ``nonprofit_check_count`` is the billing-cycle total."""
    return {
        "code": 200,
        "message": "OK",
        "errors": errors,
        "data": data,
        "timeTaken": 2 + random.randint(0, 40),
        "nonprofit_check_count": check_count,
    }


def error_envelope(code: int, message: str, errors: Any, check_count: int) -> dict[str, Any]:
    return {
        "code": code,
        "message": message,
        "errors": errors,
        "data": None,
        "timeTaken": 1,
        "nonprofit_check_count": check_count,
    }


def make_handler(state: _State, valid_key: str) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args: Any) -> None:
            """Silence the default access log; the examples own stdout."""

        def _send(
            self,
            status: int,
            body: dict[str, Any],
            headers: dict[str, str] | None = None,
        ) -> None:
            payload = json.dumps(body).encode("utf-8")
            suffix = "".join(random.choices(string.ascii_lowercase + string.digits, k=8))

            self.send_response(status)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(payload)))
            self.send_header("x-request-id", f"mock-{suffix}")

            for name, value in (headers or {}).items():
                self.send_header(name, value)

            self.end_headers()
            self.wfile.write(payload)

        def _authorized(self) -> bool:
            if self.headers.get("authorization") == f"Bearer {valid_key}":
                return True

            self._send(
                401,
                {
                    "code": 401,
                    "message": "Unauthorized",
                    "errors": [{"resource": "nonprofitcheck", "reason": "Invalid API Key"}],
                    "data": None,
                },
            )

            return False

        def _not_found(self) -> None:
            self._send(404, {"code": 404, "message": "Not Found", "errors": None, "data": None})

        def do_GET(self) -> None:
            if not self._authorized():
                return

            match = SINGLE_PATH.match(self.path)

            if match is None:
                self._not_found()
                return

            self._handle_single(match.group(1))

        def do_POST(self) -> None:
            if not self._authorized():
                return

            if self.path != BULK_PATH:
                self._not_found()
                return

            length = int(self.headers.get("content-length") or 0)
            raw = self.rfile.read(length).decode("utf-8") if length else ""

            try:
                eins = json.loads(raw) if raw.strip() else None
            except ValueError:
                eins = None

            self._handle_bulk(eins)

        def _handle_single(self, ein: str) -> None:
            if ein == CONTROL_EINS["rate_limited"]:
                self._send(
                    429,
                    error_envelope(
                        429,
                        "Too Many Requests",
                        [{"resource": "nonprofitcheck", "reason": "Rate limit exceeded"}],
                        state.checks_used_this_cycle,
                    ),
                    {"retry-after": "1"},
                )
                return

            if ein == CONTROL_EINS["transient_failure"]:
                if state.take_transient_failure():
                    self._send(
                        503,
                        error_envelope(
                            503,
                            "Service Unavailable",
                            [
                                {
                                    "resource": "nonprofitcheck",
                                    "reason": "Upstream temporarily unavailable",
                                }
                            ],
                            state.checks_used_this_cycle,
                        ),
                    )
                    return

                count = state.consume(1)
                self._send(
                    200,
                    envelope(
                        fixture_organization(FIXTURE_EINS["public_charity"]), None, count
                    ),
                )
                return

            if ein == CONTROL_EINS["slow"]:
                time.sleep(SLOW_RESPONSE_SECONDS)
                count = state.consume(1)
                self._send(
                    200,
                    envelope(
                        fixture_organization(FIXTURE_EINS["public_charity"]), None, count
                    ),
                )
                return

            if not has_fixture(ein):
                self._send(
                    404,
                    error_envelope(
                        404,
                        "Not Found",
                        [
                            {
                                "resource": "nonprofitcheck",
                                "reason": (
                                    "A nonprofit with this EIN does not exist "
                                    "in our records"
                                ),
                            }
                        ],
                        state.checks_used_this_cycle,
                    ),
                )
                return

            count = state.consume(1)
            self._send(200, envelope(fixture_organization(ein), None, count))

        def _handle_bulk(self, eins: Any) -> None:
            if not isinstance(eins, list):
                self._send(
                    400,
                    error_envelope(
                        400,
                        "Bad Request",
                        [
                            {
                                "resource": "nonprofitcheckbulk",
                                "reason": (
                                    "The nonprofit check bulk API expects an array of "
                                    "EINs as part of the HTTP POST request body"
                                ),
                            }
                        ],
                        state.checks_used_this_cycle,
                    ),
                )
                return

            if len(eins) > MAX_BULK_EINS:
                self._send(
                    400,
                    error_envelope(
                        400,
                        "Bad Request",
                        [
                            {
                                "resource": "nonprofitcheckbulk",
                                "reason": (
                                    f"A maximum of {MAX_BULK_EINS} EINs can be supplied "
                                    "to the nonprofit check bulk API"
                                ),
                            }
                        ],
                        state.checks_used_this_cycle,
                    ),
                )
                return

            # Every submitted EIN is counted, duplicates included.
            state.consume(len(eins))

            # The real service selects with `WHERE ein IN (...)`: duplicates
            # collapse to one row and the result order is the database's, not the
            # request's. Sorting here keeps that difference visible instead of
            # accidentally matching.
            matched = sorted(ein for ein in dict.fromkeys(eins) if has_fixture(ein))
            not_found = [ein for ein in eins if not has_fixture(ein)]

            # Unmatched EINs are refunded, so the count reflects records served.
            count = state.refund(len(not_found))

            if not matched:
                self._send(
                    404,
                    error_envelope(
                        404,
                        "Not Found",
                        [
                            {
                                "resource": "nonprofitcheckbulk",
                                "reason": (
                                    "There are no matching nonprofits in our records "
                                    "for this set of EINs"
                                ),
                            }
                        ],
                        count,
                    ),
                )
                return

            errors = (
                None
                if not not_found
                else [
                    {
                        "resource": "nonprofitcheckbulk",
                        "reason": (
                            "There are no matching nonprofits in our records for this "
                            "set of EINs"
                        ),
                        "code": 404,
                        "eins": not_found,
                    }
                ]
            )

            self._send(
                200, envelope([fixture_organization(ein) for ein in matched], errors, count)
            )

    return Handler


def start_mock_server(port: int = 0, api_key: str | None = None) -> ThreadingHTTPServer:
    """
    Starts the mock API on a background thread.

    :param port: ``0`` picks a free port.
    :param api_key: Key the server accepts. Defaults to ``mock-key``.
    """
    valid_key = api_key or os.environ.get("MOCK_API_KEY") or "mock-key"
    server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(_State(), valid_key))
    server.daemon_threads = True

    threading.Thread(target=server.serve_forever, daemon=True).start()

    return server


def base_url_for(server: ThreadingHTTPServer) -> str:
    """The loopback URL the server is listening on. Always bound to 127.0.0.1."""
    port = server.server_address[1]

    return f"http://127.0.0.1:{port}"


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the Pactman mock API.")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--api-key", default=None)
    args = parser.parse_args()

    server = start_mock_server(args.port, args.api_key)
    print(f"Mock Pactman API listening on {base_url_for(server)}")

    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
