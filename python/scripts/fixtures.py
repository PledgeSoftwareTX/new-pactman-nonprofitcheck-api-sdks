"""
Fixture organizations for the examples and the mock server.

Scenarios like a revoked exemption, an OFAC match, a cross-source conflict or an
unknown future field cannot be summoned on demand from the production API. They
are declared here once so an example can demonstrate the handling and the mock
server can serve the record.

Field names and values mirror the shapes documented in the Pactman API
reference. The EINs are illustrative and are not real organizations.
"""

from __future__ import annotations

import copy
import re
import time
from typing import Any

OFAC_NO_MATCH = (
    "This organization was NOT included in the Office of Foreign Assets Control "
    "Specially Designated Nationals (SDN) list."
)
"""The two OFAC sentences the API returns. It reports prose, not a boolean."""

OFAC_POSSIBLE_MATCH = (
    "This organization may be included in the Office of Foreign Assets Control "
    "Specially Designated Nationals(SDN) list. A close match was found with the "
    "Special Designated National with UID: 41234"
)

FIXTURE_EINS = {
    # A 501(c)(3) public charity with every source returned and nothing adverse.
    "public_charity": "411787097",
    # A second clean organization, for bulk examples.
    "public_charity_second": "996589560",
    # A 501(c)(3) private foundation — different foundation and filing codes.
    "private_foundation": "042103594",
    # A record with most optional identity fields returned as null.
    "sparse_identity": "060646700",
    # Address fields that are present but disagree with each other.
    "inconsistent_address": "311580204",
    # Every source date is old, for the freshness and re-review examples.
    "stale_data": "362167048",
    # Listed in the IRS Automatic Revocation of Exemption data, not reinstated.
    "revoked": "237112796",
    # Revoked and subsequently reinstated — both dates present.
    "reinstated": "133039601",
    # A possible OFAC SDN match.
    "ofac_match": "954367818",
    # OFAC screening returned no value for this organization.
    "ofac_unavailable": "061553389",
    # BMF and Publication 78 disagree; `irs_bmf_pub78_conflict` is true.
    "conflicted": "521693387",
    # Carries fields and an enum value this SDK version does not know about.
    "future_fields": "237324370",
    # Well-formed, but no record exists.
    "no_record": "999999999",
}
"""Named EINs the examples refer to, so no example hard-codes a bare number."""

CONTROL_EINS = {
    # Always answers HTTP 429 with `Retry-After: 1`.
    "rate_limited": "900000429",
    # Answers HTTP 503 twice, then succeeds.
    "transient_failure": "900000503",
    # Holds the response open, so a short timeout expires.
    "slow": "900000408",
}
"""EINs the mock server answers with a specific failure, for the error examples."""

DEDUCTIBILITY_PUBLIC_CHARITY = {
    "organization_type": (
        "Deductions for donations to public charities are generally limited to 50 "
        "percent of adjusted gross income (AGI). This limit increases to 60% of AGI "
        "for cash donations. For Non-Cash assets held for more than one year, the "
        "limit is 30% of AGI."
    ),
    "deductibility_limitation": "50%",
    "deductibility_status_description": "PC",
}

DEDUCTIBILITY_PRIVATE_FOUNDATION = {
    "organization_type": (
        "Deductions for donations to private foundations are generally limited to 30 "
        "percent of adjusted gross income (AGI). For Non-Cash assets held for more "
        "than one year, the limit is 20% of AGI."
    ),
    "deductibility_limitation": "30%",
    "deductibility_status_description": "PF",
}


def api_date(days_ago: float) -> str:
    """
    The API formats every date as ``M/DD/YYYY h:mm:ss AM``.

    Fixture dates are generated relative to today so the freshness examples stay
    meaningful however long after they were written they are run.
    """
    moment = time.localtime(time.time() - days_ago * 86_400)
    clock = time.strftime("%I:%M:%S %p", moment).lstrip("0")

    return f"{moment.tm_mon}/{moment.tm_mday:02d}/{moment.tm_year} {clock}"


def _slug(name: str) -> str:
    return re.sub(r"^-|-$", "", re.sub(r"[^a-z0-9]+", "-", name.lower()))


def _public_charity(
    ein: str,
    name: str,
    overrides: dict[str, Any] | None = None,
    omit: list[str] | None = None,
) -> dict[str, Any]:
    """
    A complete, unremarkable public charity. Scenarios override from here.

    :param omit: Keys to delete outright, so the record can express "the API
        returned no field at all" as distinct from "the API returned null".
    """
    organization: dict[str, Any] = {
        "pactman_org_url": f"https://pactman.org/profile/nonprofit/{_slug(name)}-{ein[-4:]}",
        "organization_info_last_modified": api_date(40),
        "ein": ein,
        "organization_name": name.upper(),
        "organization_name_aka": None,
        "address_line1": "50 LOWELL AVE",
        "address_line2": "APT 3B",
        "city": "WESTFIELD",
        "state": "MA",
        "state_name": "Massachusetts",
        "zip": "01085-2643",
        "filing_req_code": "01",
        "pub78_church_message": None,
        "pub78_organization_name": name,
        "pub78_ein": ein,
        "pub78_verified": True,
        "pub78_city": "Westfield",
        "pub78_state": "MA",
        "pub78_indicator": "0",
        "pub78_source_org_type_1": "PC",
        "pub78_source_org_type_2": None,
        "pub78_source_org_type_3": None,
        "organization_types": [DEDUCTIBILITY_PUBLIC_CHARITY],
        "most_recent_pub78": api_date(26),
        "bmf_church_message": None,
        "bmf_organization_name": name.upper(),
        "bmf_ein": ein,
        "bmf_status": True,
        "bmf_city": "WESTFIELD",
        "bmf_state": "MA",
        "bmf_street_address": "50 LOWELL AVE APT 3B",
        "bmf_subsection": "03",
        "bmf_source_pf_filing_req_cd": "0",
        "bmf_deductability_text": "Contributions are deductible",
        "most_recent_bmf": api_date(20),
        "subsection_description": "501(c)(3) Public Charity",
        "foundation_code": "10",
        "foundation_code_description": "Public charity described in section 509(a)(1) or (2)",
        "foundation_type_code": "pc",
        "foundation_type_description": "Public charity described in section 509(a)(1) or (2)",
        "foundation_509a_status": "N/A",
        "ruling_month": "07",
        "ruling_year": "2024",
        "group_exemption": "0000",
        "exempt_status_code": "01",
        "ofac_status": OFAC_NO_MATCH,
        "ofac_list_published_date": api_date(5),
        "revocation_code": None,
        "revocation_date": None,
        "reinstatement_date": None,
        "aroe_list_published_date": api_date(12),
        "irs_bmf_pub78_conflict": False,
        "report_date": api_date(0),
    }
    organization.update(overrides or {})

    for key in omit or []:
        organization.pop(key, None)

    return organization


FIXTURE_ORGANIZATIONS: dict[str, dict[str, Any]] = {
    FIXTURE_EINS["public_charity"]: _public_charity(
        FIXTURE_EINS["public_charity"],
        "Meals Today Example Nonprofit",
        {
            "organization_name_aka": "MEALS TODAY E.N",
            "pub78_organization_name": "Meals Today Example Nonprofit, Inc.",
        },
    ),
    FIXTURE_EINS["public_charity_second"]: _public_charity(
        FIXTURE_EINS["public_charity_second"],
        "Aborjaily Example Nonprofit",
        {
            "organization_name_aka": "ABORJAILY E.N",
            "city": "SPRINGFIELD",
            "pub78_city": "Springfield",
            "zip": "01103-1420",
            "address_line1": "19 HAMPDEN ST",
            "address_line2": None,
            "bmf_street_address": "19 HAMPDEN ST",
        },
    ),
    FIXTURE_EINS["private_foundation"]: _public_charity(
        FIXTURE_EINS["private_foundation"],
        "Hartwell Family Example Foundation",
        {
            "organization_name_aka": None,
            # A private foundation files a 990-PF, tracked in the PF field below
            # rather than in the general 990 filing requirement.
            "filing_req_code": "00",
            "pub78_source_org_type_1": "PF",
            "organization_types": [DEDUCTIBILITY_PRIVATE_FOUNDATION],
            "bmf_source_pf_filing_req_cd": "1",
            "bmf_deductability_text": "Contributions are deductible",
            "subsection_description": "501(c)(3) Private Foundation",
            "foundation_code": "04",
            "foundation_code_description": "Private non-operating foundation",
            "foundation_type_code": "pf",
            "foundation_type_description": "Private non-operating foundation",
            "foundation_509a_status": "N/A",
            "ruling_month": "11",
            "ruling_year": "1998",
        },
    ),
    # Optional identity fields the API had no value for. `null` here means "the
    # API returned no value", which is not the same as "this did not match".
    FIXTURE_EINS["sparse_identity"]: _public_charity(
        FIXTURE_EINS["sparse_identity"],
        "Quiet Harbor Example Trust",
        {
            "organization_name_aka": None,
            "address_line1": "PO BOX 118",
            "address_line2": None,
            "city": "ROCKPORT",
            "state": "ME",
            "state_name": None,
            "zip": None,
            "pub78_city": None,
            "pub78_state": None,
            "bmf_city": None,
            "bmf_state": None,
            "bmf_street_address": None,
            "group_exemption": None,
            "ruling_month": None,
            "ruling_year": None,
        },
        # No OFAC keys at all: the source was not reported for this organization,
        # which is not the same as a null status or a no-match result.
        ["ofac_status", "ofac_list_published_date"],
    ),
    # Every address component is present, and they contradict one another: the
    # state code says Massachusetts, the state name and the ZIP say Maine, and
    # address_line2 holds a placeholder. Transcription damage of this kind
    # survives any check that only asks whether a field came back non-null.
    FIXTURE_EINS["inconsistent_address"]: _public_charity(
        FIXTURE_EINS["inconsistent_address"],
        "Harbor Light Example Alliance",
        {
            "organization_name_aka": None,
            "address_line1": "12 SEA STREET",
            "address_line2": "N/A",
            "city": "ROCKPORT",
            "state": "MA",
            "state_name": "Maine",
            "zip": "04856",
            "pub78_city": "Rockport",
            "pub78_state": "MA",
            "bmf_city": "ROCKPORT",
            "bmf_state": "MA",
            "bmf_street_address": "12 SEA STREET",
        },
    ),
    # Nothing adverse, but every source is well out of date. A workflow with a
    # re-review rule should notice this even though the findings look clean.
    FIXTURE_EINS["stale_data"]: _public_charity(
        FIXTURE_EINS["stale_data"],
        "Long Quiet Example Foundation",
        {
            "organization_info_last_modified": api_date(700),
            "most_recent_pub78": api_date(640),
            "most_recent_bmf": api_date(610),
            "ofac_list_published_date": api_date(580),
            "aroe_list_published_date": api_date(560),
        },
    ),
    FIXTURE_EINS["revoked"]: _public_charity(
        FIXTURE_EINS["revoked"],
        "Lapsed Filings Example Society",
        {
            "organization_name_aka": None,
            "pub78_verified": False,
            "pub78_indicator": None,
            "organization_types": None,
            "bmf_status": False,
            "bmf_deductability_text": "Contributions are not deductible",
            "subsection_description": "501(c)(3) Public Charity",
            "exempt_status_code": "25",
            "revocation_code": "01",
            "revocation_date": api_date(1_260),
            "reinstatement_date": None,
        },
    ),
    FIXTURE_EINS["reinstated"]: _public_charity(
        FIXTURE_EINS["reinstated"],
        "Second Chance Example Alliance",
        {
            "organization_name_aka": "SECOND CHANCE E.A",
            "revocation_code": "01",
            "revocation_date": api_date(1_260),
            "reinstatement_date": api_date(520),
        },
    ),
    FIXTURE_EINS["ofac_match"]: _public_charity(
        FIXTURE_EINS["ofac_match"],
        "Overseas Relief Example Fund",
        {
            "organization_name_aka": "OVERSEAS RELIEF E.F",
            "ofac_status": OFAC_POSSIBLE_MATCH,
        },
    ),
    # The API returned nothing for OFAC. Absent is not the same as "no match".
    FIXTURE_EINS["ofac_unavailable"]: _public_charity(
        FIXTURE_EINS["ofac_unavailable"],
        "Riverbend Example Coalition",
        {"ofac_status": None, "ofac_list_published_date": None},
    ),
    # BMF says exempt, Publication 78 does not list the organization, and the API
    # flags the disagreement rather than picking a winner.
    FIXTURE_EINS["conflicted"]: _public_charity(
        FIXTURE_EINS["conflicted"],
        "Crosscheck Example Institute",
        {
            "organization_name": "CROSSCHECK EXAMPLE INSTITUTE",
            "pub78_organization_name": None,
            "pub78_ein": None,
            "pub78_verified": False,
            "pub78_city": None,
            "pub78_state": None,
            "pub78_indicator": None,
            "organization_types": None,
            "most_recent_pub78": api_date(26),
            "bmf_organization_name": "CROSSCHECK EXAMPLE INST",
            "bmf_status": True,
            "irs_bmf_pub78_conflict": True,
        },
    ),
    # A response from a newer API version: fields this SDK has never heard of,
    # and an enum value outside the documented set.
    FIXTURE_EINS["future_fields"]: _public_charity(
        FIXTURE_EINS["future_fields"],
        "Forward Compatible Example Trust",
        {
            "foundation_type_code": "zz",
            "foundation_type_description": (
                "A classification added after this SDK was published"
            ),
            "organization_types": [
                {
                    **DEDUCTIBILITY_PUBLIC_CHARITY,
                    "deductibility_status_description": "XX",
                    "future_deductibility_note": "An unknown member of a known object",
                }
            ],
            "state_charity_registration_status": "ACTIVE",
            "watchlist_screening": {
                "provider": "example",
                "matches": 0,
                "list_published_date": api_date(5),
            },
        },
    ),
}
"""Every organization the mock server can return, keyed by EIN."""

KNOWN_NONPROFIT_FIELDS = frozenset(FIXTURE_ORGANIZATIONS[FIXTURE_EINS["public_charity"]])
"""
Every field the documented schema defines on an organization.

Used to detect drift: anything the live API returns that is not in this set is a
field newer than this SDK. That is not an error — see ``ex_25`` — but it is
worth knowing about.
"""


def has_fixture(ein: str) -> bool:
    """True when the mock server has a record for this EIN."""
    return ein in FIXTURE_ORGANIZATIONS


def fixture_organization(ein: str) -> dict[str, Any] | None:
    """A defensive copy, so an example mutating a record cannot affect later calls."""
    record = FIXTURE_ORGANIZATIONS.get(ein)

    return copy.deepcopy(record) if record is not None else None
