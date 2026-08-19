"""
EX-20 — Bulk batch-size validation.

The batch limit is the server's. The SDK exports it as ``MAX_BULK_EINS`` and
checks against it locally, so an over-limit batch fails in-process instead of
spending a round trip to be told no.

``MAX_BULK_EINS`` is declared once in the SDK. Import it — do not copy the number
into your own constants file, where it will outlive the server's.

Run:  PACTMAN_API_KEY=... python examples/ex_20_bulk_batch_limits.py
"""

from __future__ import annotations

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note

from pactman_nonprofit_check_plus import (
    MAX_BULK_EINS,
    PactmanBadRequestError,
    PactmanValidationError,
)


def batch_of_size(size: int) -> list[str]:
    """Fills a batch with well-formed EINs, so only the size is under test."""
    return [str(100000000 + index) for index in range(size)]


def main() -> int:
    with fixture_api() as client:
        heading("The authoritative limit")
        field("MAX_BULK_EINS", MAX_BULK_EINS)
        bullet("Exported by the SDK, mirroring the server-side maximum.")
        bullet("Referenced here; not redeclared.")

        heading("Empty collection")

        try:
            client.nonprofits.check_bulk([])
            print("  Unexpectedly accepted.")
        except PactmanValidationError as error:
            field("class", type(error).__name__)
            field("origin", error.origin)
            field("message", error.message)
            field("request sent", "no")

        heading(f"Over-limit collection ({MAX_BULK_EINS + 1} EINs)")

        try:
            client.nonprofits.check_bulk(batch_of_size(MAX_BULK_EINS + 1))
            print("  Unexpectedly accepted.")
        except PactmanValidationError as error:
            field("class", type(error).__name__)
            field("origin", error.origin)
            field("message", error.message)
            field("request sent", "no")

        heading(f"At the limit ({MAX_BULK_EINS} EINs)")

        # Accepted locally and sent. Most of these EINs have no record, so this
        # comes back as a partial success — the size was never the problem.
        at_limit = [FIXTURE_EINS["public_charity"], *batch_of_size(MAX_BULK_EINS - 1)]

        result = client.nonprofits.check_bulk(at_limit)

        field("EINs sent", len(at_limit))
        field("status", result.status)
        field("organizations returned", len(result.organizations))
        field("not_found_eins", len(result.not_found_eins))

        # If the server ever tightens its limit below the SDK's, the local check
        # will pass and the server will answer 400. That message is
        # authoritative; surface it rather than trusting the constant.
        heading("If the server disagrees with the constant")
        bullet("A server-side rejection arrives as PactmanBadRequestError.")
        bullet("`api_errors[]['reason']` carries the limit the server actually enforces.")
        bullet(f"Catch {PactmanBadRequestError.__name__} and log the reason verbatim.")

        # Chunking is your decision, not the SDK's: it refuses to split a batch,
        # because doing so quietly turns one billable request into several.
        heading("Splitting a larger list")

        large_list = batch_of_size(120)
        batches = [
            large_list[index : index + MAX_BULK_EINS]
            for index in range(0, len(large_list), MAX_BULK_EINS)
        ]

        field("input size", len(large_list))
        field("batches", len(batches))
        field("batch sizes", ", ".join(str(len(batch)) for batch in batches))
        bullet(
            "The SDK never chunks for you — each batch below is a request you chose to make."
        )

    note(
        "One constant, imported everywhere. A hardcoded 50 scattered through a codebase\n"
        "is a migration waiting to be missed."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
