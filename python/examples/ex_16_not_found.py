"""
EX-16 — EIN not found, and application-level failures.

A well-formed EIN with no matching record is a normal outcome, not a bug. The
single endpoint answers HTTP 404, which the SDK raises as
:class:`PactmanNotFoundError` — a subclass of :class:`PactmanApiError`, so a
handler can catch the specific case or the general one.

The envelope's own ``code``, ``message`` and ``errors`` survive onto the error,
and none of the diagnostics contain the API key.

Run:  PACTMAN_API_KEY=... python examples/ex_16_not_found.py
"""

from __future__ import annotations

import json
import os
import traceback

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note

from pactman_nonprofit_check_plus import (
    PactmanApiError,
    PactmanErrorCategory,
    PactmanNotFoundError,
    is_pactman_error,
)


def main() -> int:
    api_key = os.environ.get("PACTMAN_API_KEY", "")

    with fixture_api() as client:
        heading(f"Single check for {FIXTURE_EINS['no_record']} — well formed, no record")

        try:
            result = client.nonprofits.check(FIXTURE_EINS["no_record"])
            name = result.nonprofit.get("organization_name") if result.nonprofit else None
            print(f"  Unexpectedly succeeded: {name}")
        except PactmanNotFoundError as error:
            # Stable identity: class, category, and origin. Never parse `message`.
            field("class", type(error).__name__)
            field("category", error.category)
            field("origin", error.origin)
            field("is a PactmanApiError", isinstance(error, PactmanApiError))
            field("is_pactman_error", is_pactman_error(error))
            field(
                "matches NotFound category",
                error.category is PactmanErrorCategory.NOT_FOUND,
            )

            heading("  Response detail carried on the error")
            field("status", error.status)
            field("api_code (envelope code)", error.api_code)
            field("api_message", error.api_message)
            field("request_id", error.request_id)
            field("attempts", error.attempts)
            field("retry_after_seconds", error.retry_after_seconds)

            for detail in error.api_errors:
                bullet(
                    f"resource={detail.get('resource')} code={detail.get('code', '-')}"
                    f" reason={detail.get('reason')}"
                )

            # Sanitized diagnostics: safe to log, safe to attach to a ticket.
            heading("  error.to_dict() — what you can safely log")

            for line in json.dumps(error.to_dict(), indent=2, default=str).splitlines():
                print(f"    {line}")

            serialized = json.dumps(error.to_dict(), default=str) + "".join(
                traceback.format_exception(type(error), error, error.__traceback__)
            )
            field("contains the API key", bool(api_key) and api_key in serialized)

            # 404 is never retried, whatever the retry policy says.
            field("attempts made", f"{error.attempts} — not-found is not a transient failure")

        # The bulk endpoint behaves differently, and this is the part that
        # surprises people: unmatched EINs come back on a successful 200 as
        # item-level errors. Only a request where *nothing* matched is a 404.
        heading("Bulk — mixed input returns HTTP 200, not an error")

        mixed = client.nonprofits.check_bulk(
            [FIXTURE_EINS["public_charity"], FIXTURE_EINS["no_record"]]
        )

        field("status", mixed.status)
        field("organizations returned", len(mixed.organizations))
        field("not_found_eins", ", ".join(mixed.not_found_eins))

        heading("Bulk — nothing matched at all")

        try:
            client.nonprofits.check_bulk([FIXTURE_EINS["no_record"]])
            print("  Unexpectedly succeeded.")
        except PactmanApiError as error:
            field("class", type(error).__name__)
            field("status", error.status)
            field("api_message", error.api_message)

    note(
        'Distinguish "we could not find it" from "we could not ask". A 404 means the\n'
        "record is absent; a timeout or a 503 means you learned nothing. Only the first\n"
        "is a fact about the organization."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
