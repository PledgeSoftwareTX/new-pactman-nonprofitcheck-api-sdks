"""
EX-29 — Pre-payment or pre-disbursement recheck.

An organization approved at onboarding is not an organization approved today.
Exemptions get revoked, sanctions lists get republished, and IRS data lands on
its own schedule — all of it after your approval and before your payout.

This example rechecks immediately before the money moves, compares the fresh
findings with the stored ones, and pauses the workflow on a material change. Both
sets of evidence are kept: the payout is defensible only if you can show what you
knew, and when.

Run:  PACTMAN_API_KEY=... python examples/ex_29_pre_disbursement_recheck.py
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note, render
from lib.screening import collect_findings, concerns, diff_findings

from pactman_nonprofit_check_plus import PactmanError

BLOCKING_CHANGES = {
    "revocation_code",
    "revocation_date",
    "ofac_state",
    "bmf_status",
    "pub78_verified",
    "irs_bmf_pub78_conflict",
}
"""Changes that stop a disbursement outright at this organization."""


def _good_standing(name: str) -> dict[str, Any]:
    return {
        "organization_name": name,
        "bmf_status": True,
        "exempt_status_code": "01",
        "pub78_verified": True,
        "revocation_code": None,
        "revocation_date": None,
        "reinstatement_date": None,
        "ofac_state": "no_match",
        "irs_bmf_pub78_conflict": False,
        "foundation_type_code": "pc",
        "subsection_description": "501(c)(3) Public Charity",
    }


STORED_VERIFICATIONS: dict[str, dict[str, Any]] = {
    FIXTURE_EINS["public_charity"]: {
        "approved_at": "2026-02-11T14:05:00+00:00",
        "request_id": "req-onboarding-8841",
        "findings": _good_standing("MEALS TODAY EXAMPLE NONPROFIT"),
    },
    # Approved while in good standing. The IRS data now says otherwise.
    FIXTURE_EINS["revoked"]: {
        "approved_at": "2026-01-06T10:22:00+00:00",
        "request_id": "req-onboarding-7310",
        "findings": _good_standing("LAPSED FILINGS EXAMPLE SOCIETY"),
    },
}
"""
Verification evidence stored when each payee was approved.

Store the findings, not a verdict: "approved" alone cannot be re-examined.
"""

PENDING_DISBURSEMENTS: list[dict[str, Any]] = [
    {"payment_id": "PAY-5501", "ein": FIXTURE_EINS["public_charity"], "amount": 12_400},
    {"payment_id": "PAY-5502", "ein": FIXTURE_EINS["revoked"], "amount": 3_150},
]


def main() -> int:
    releases: list[dict[str, Any]] = []

    with fixture_api() as client:
        for payment in PENDING_DISBURSEMENTS:
            heading(
                f"{payment['payment_id']} — ${payment['amount']:,} to {payment['ein']}"
            )

            stored = STORED_VERIFICATIONS.get(payment["ein"])

            try:
                # Retries stay on: a transient failure here should be absorbed,
                # not turned into a false "changed" signal.
                result = client.nonprofits.check(payment["ein"], timeout=10.0)
            except PactmanError as error:
                # Could not verify. That is a hold, never a release — an
                # unreachable API is not evidence that anything is fine.
                field("recheck", f"failed: {type(error).__name__}")
                field("decision", "HOLD — the payee could not be re-verified before payout")
                releases.append({**payment, "decision": "hold", "reason": "recheck_failed"})
                continue

            if result.nonprofit is None:
                field("recheck", "no record returned")
                field("decision", "HOLD — the payee no longer returns a record")
                releases.append({**payment, "decision": "hold", "reason": "no_record"})
                continue

            current = collect_findings(result.nonprofit)
            changes = diff_findings(stored["findings"] if stored else None, current)
            blocking = [change for change in changes if change["field"] in BLOCKING_CHANGES]
            issues = concerns(current, stale_after_days=120)

            field("approved at", stored["approved_at"] if stored else None)
            field("rechecked at", datetime.now(timezone.utc).isoformat())
            field("fields changed since approval", len(changes))

            for change in changes:
                marker = "   [blocking]" if change["field"] in BLOCKING_CHANGES else ""
                bullet(
                    f"{change['field']}: {render(change['before'])}"
                    f" → {render(change['after'])}{marker}"
                )

            if not changes:
                bullet("no material field changed")

            for issue in issues:
                bullet(f"current concern: {issue}")

            decision = "hold" if blocking or issues else "release"

            field(
                "decision",
                "RELEASE — findings are unchanged and no concern is open"
                if decision == "release"
                else "HOLD — a material change or open concern was found before payout",
            )

            # Both snapshots are kept. Neither overwrites the other.
            releases.append(
                {
                    **payment,
                    "decision": decision,
                    "prior_verification": stored,
                    "current_verification": {
                        "checked_at": datetime.now(timezone.utc).isoformat(),
                        "request_id": result.request_id,
                        "report_date": result.nonprofit.get("report_date"),
                        "findings": current,
                    },
                    "changes": changes,
                    "blocking_changes": [change["field"] for change in blocking],
                }
            )

    heading("Payment run")

    for release in releases:
        blocked = release.get("blocking_changes") or []
        detail = f"blocked by: {', '.join(blocked)}" if blocked else ""
        print(
            f"  {release['payment_id']}  {release['ein']}"
            f"  {release['decision'].upper().ljust(8)} {detail}"
        )

    held = [release for release in releases if release["decision"] == "hold"]

    field("\nreleased", len(releases) - len(held))
    field("held for review", len(held))
    bullet("Each held payment retains the prior and the current verification evidence.")

    note(
        "Recheck as close to the money movement as your workflow allows. A check from\n"
        "onboarding proves what was true at onboarding, and a payout is a decision made\n"
        "today."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
