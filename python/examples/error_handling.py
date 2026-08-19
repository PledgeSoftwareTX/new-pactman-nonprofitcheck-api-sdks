"""
Branching on error type: local validation, authentication, and rate limits.

Run:  PACTMAN_API_KEY=... python examples/error_handling.py
"""

from __future__ import annotations

import os
import sys

from pactman_nonprofit_check_plus import (
    PactmanApiError,
    PactmanAuthenticationError,
    PactmanClient,
    PactmanNetworkError,
    PactmanRateLimitError,
    PactmanTimeoutError,
    PactmanValidationError,
)


def explain(error: Exception) -> str:
    """One place to turn any SDK failure into an action. No string parsing."""
    if isinstance(error, PactmanValidationError):
        detail = " ".join(issue.message for issue in error.issues) or error.message
        return f"Local validation — fix the input. {detail}"

    if isinstance(error, PactmanAuthenticationError):
        return "Authentication — the API key was rejected. Check PACTMAN_API_KEY."

    if isinstance(error, PactmanRateLimitError):
        seconds = error.retry_after_seconds
        after = "an unspecified" if seconds is None else seconds
        return f"Rate limited — retry after {after} seconds."

    if isinstance(error, PactmanTimeoutError):
        return f"Timed out after {error.timeout}s — raise the timeout or retry later."

    if isinstance(error, PactmanNetworkError):
        return "Network failure — the request never reached the API."

    if isinstance(error, PactmanApiError):
        request = error.request_id or "unknown"
        return f"API error {error.status} (request {request}): {error.message}"

    return f"Unexpected: {error}"


def main() -> int:
    api_key = os.environ.get("PACTMAN_API_KEY")

    if not api_key:
        print("Set PACTMAN_API_KEY before running this example.", file=sys.stderr)
        return 1

    base_url = os.environ.get("PACTMAN_BASE_URL")

    with PactmanClient(
        api_key=api_key, base_url=base_url, timeout=10.0, retry={"max_retries": 2}
    ) as client:
        # 1. A malformed EIN never leaves the process.
        try:
            client.nonprofits.check("41178709")
        except Exception as error:
            print("malformed EIN ->", explain(error))

        # 2. An empty batch is rejected locally too.
        try:
            client.nonprofits.check_bulk([])
        except Exception as error:
            print("empty batch   ->", explain(error))

        # 3. A bad key produces an authentication error on first use.
        try:
            with PactmanClient(
                api_key="obviously-not-a-real-key", base_url=base_url, retry=False
            ) as bad_client:
                bad_client.nonprofits.check("411787097")

            print("bad key       -> unexpectedly succeeded")
        except Exception as error:
            print("bad key       ->", explain(error))

        # 4. A real call, handled the same way.
        try:
            result = client.nonprofits.check("41-1787097")
            name = result.nonprofit["organization_name"] if result.nonprofit else "no record"
            print("valid check   ->", name)
        except Exception as error:
            print("valid check   ->", explain(error))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
