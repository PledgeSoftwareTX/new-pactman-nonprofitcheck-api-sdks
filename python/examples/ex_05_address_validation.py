"""
EX-05 — Validating the address the API returned.

The response carries ``address_line1``, ``address_line2``, ``city``, ``state``,
``state_name`` and ``zip``. This example asks one question about them: is this
address well-formed and self-consistent enough to act on?

Three outcomes, and the middle one is the point:

- ``usable`` — every required component came back, and nothing contradicts
- ``incomplete`` — a required component was not returned; absence, not error
- ``inconsistent`` — the components came back and disagree with each other

A record can be complete and wrong. ``state`` and ``state_name`` are two fields
for one fact, and a ZIP already encodes the state a third time, so an extract
that has been transcribed, merged or truncated can contradict itself while every
field passes a null check.

Well-formed is not deliverable. Nothing here asks USPS whether mail arrives; see
the closing note for where that call would go.

Run:  PACTMAN_API_KEY=... python examples/ex_05_address_validation.py
"""

from __future__ import annotations

from lib.address import ADDRESS_COMPONENTS, is_usable, validate_address
from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note, pick

SUBJECTS = [
    ("Complete record", FIXTURE_EINS["public_charity"]),
    ("Sparse record — components not returned", FIXTURE_EINS["sparse_identity"]),
    ("Complete record that disagrees with itself", FIXTURE_EINS["inconsistent_address"]),
]
"""One clean record, one with components missing, one that contradicts itself."""

MARKS = {"pass": "✓", "fail": "✗", "not_checkable": "·"}


def route(verdict: str) -> str:
    """Your policy, not the SDK's. This one refuses to treat absence as validity."""
    if verdict == "usable":
        return "continue — the address is complete and self-consistent"

    if verdict == "incomplete":
        return "manual review — too little address data came back to act on"

    return "manual review — the returned components contradict each other"


def main() -> int:
    with fixture_api() as client:
        for label, ein in SUBJECTS:
            nonprofit = client.nonprofits.check(ein).nonprofit

            if nonprofit is None:
                print(f"No record for {ein}.")
                continue

            heading(
                f"{label} — {pick(nonprofit, 'organization_name')} ({pick(nonprofit, 'ein')})"
            )

            # What came back, before any judgement. `<null>` and `<not returned>`
            # print differently here for the same reason they do everywhere else.
            for component in ADDRESS_COMPONENTS:
                field(component, pick(nonprofit, component), 16)

            result = validate_address(nonprofit)

            print("\n  checks:")

            for entry in result.checks:
                # A check that could not run is marked apart from one that
                # passed. An unrunnable check has confirmed nothing.
                bullet(
                    f"{MARKS[entry.outcome]} {entry.label.ljust(38)} "
                    f"{entry.outcome.ljust(14)}{entry.detail or ''}".rstrip()
                )

            print("")
            field("components not returned", ", ".join(result.missing) or "<none>")
            field(
                "checks failed",
                ", ".join(entry.id for entry in result.failures) or "<none>",
            )
            field("verdict", result.verdict)
            field("routed to", route(result.verdict))

            if is_usable(result.verdict):
                # Only now is it reasonable to store this as the organization's
                # address, and even now it is the IRS filing address, not proof
                # of an occupant.
                field("safe to persist as-is", "yes — no component is missing or contradicted")

    note(
        "Complete is not the same as correct, and correct is not the same as deliverable.\n"
        "These checks are structural: they run offline, need no second credential, and\n"
        "catch the damage that survives a null check. A deliverability verdict — USPS,\n"
        "Lob, Smarty, Google Address Validation — is a network call with its own key,\n"
        "and it belongs as one more check inside validate_address(), not as a\n"
        "replacement for these. Bear in mind what a failure there would mean: an IRS\n"
        "filing address is often a PO box, an accountant or a registered agent, so a\n"
        "deliverability miss is a fact about the mailbox, never about the charity."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
