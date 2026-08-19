"""
EX-18 — Bulk input order and duplicate EINs.

Three things worth knowing before you zip a bulk response against your input:

1. The SDK sends your EINs in the order you supplied them, duplicates included.
   It does not reorder and it does not deduplicate.
2. The API matches by set membership. Response order is not guaranteed to follow
   request order, and a duplicated EIN comes back once. Index results by EIN;
   never pair them positionally.
3. ``nonprofit_check_count`` is not the count of unique EINs you sent. Do not
   reconstruct usage from your input — read the number the API reports.

Run:  PACTMAN_API_KEY=... python examples/ex_18_bulk_order_and_duplicates.py
"""

from __future__ import annotations

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note


def main() -> int:
    # Deliberately unsorted, with one EIN repeated twice.
    requested = [
        FIXTURE_EINS["public_charity_second"],
        FIXTURE_EINS["public_charity"],
        FIXTURE_EINS["public_charity_second"],
        FIXTURE_EINS["private_foundation"],
    ]

    with fixture_api() as client:
        heading("Sent as supplied — no reordering, no deduplication")

        for index, ein in enumerate(requested):
            bullet(f"[{index}] {ein}")

        field("unique EINs", len(set(requested)))
        field("EINs sent", len(requested))

        before = client.nonprofits.check(FIXTURE_EINS["public_charity"])
        result = client.nonprofits.check_bulk(requested)

        heading("Returned")

        for index, org in enumerate(result.organizations):
            bullet(f"[{index}] {org.get('ein')}  {org.get('organization_name')}")

        returned_order = [org.get("ein") for org in result.organizations]
        request_order_unique = list(dict.fromkeys(requested))

        field("response length", len(returned_order))
        field("request length", len(requested))
        field("positional pairing valid", returned_order == requested)
        field("matches request order (deduped)", returned_order == request_order_unique)

        # The correct way to consume a bulk response.
        by_ein = {org.get("ein"): org for org in result.organizations}

        heading("Indexed by EIN — the pairing that always holds")

        for index, ein in enumerate(requested):
            matched = by_ein.get(ein)
            name = matched.get("organization_name") if matched else "no record returned"
            repeated = requested.index(ein) != index
            duplicate = "   (duplicate of an earlier input)" if repeated else ""
            print(f"  input[{index}] {ein} → {name}{duplicate}")

        heading("Usage is reported, not inferred")
        field("unique EINs submitted", len(set(requested)))
        field("total EINs submitted", len(requested))
        field("organizations returned", len(result.organizations))
        field("check_count before this call", before.check_count)
        field("check_count after this call", result.check_count)
        field(
            "delta",
            result.check_count - before.check_count
            if before.check_count is not None and result.check_count is not None
            else "<not reported>",
        )

        bullet("Each submitted EIN is billable, duplicates included.")
        bullet("The delta above is the authority on what this request consumed.")
        bullet("Deriving usage from your unique-input count will disagree with the invoice.")

        # Opt in when duplicates are an artifact of your data rather than intent.
        heading("Opting in to deduplication")

        deduped = client.nonprofits.check_bulk(requested, dedupe=True)

        field("EINs sent after dedupe", len(set(requested)))
        field("organizations returned", len(deduped.organizations))
        field("check_count", deduped.check_count)
        field(
            "delta",
            deduped.check_count - result.check_count
            if result.check_count is not None and deduped.check_count is not None
            else "<not reported>",
        )

    note(
        "Deduplication is off by default because collapsing a list silently would\n"
        "misreport what was checked. Pass dedupe=True when you mean it."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
