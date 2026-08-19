"""
Grouped views over the source-specific findings on a :class:`.Nonprofit`.

These are projections, not derivations: every key is copied 1:1 from a field the
API returned. Nothing here computes an "approved", "eligible" or "safe" verdict,
and nothing infers a value from another field.

Each accessor returns ``None`` when the API returned no data at all for that
source. That keeps "the source was not returned" distinguishable from an
explicit negative such as ``pub78_verified: False`` or a ``None`` field.
"""

from __future__ import annotations

from typing import Any, TypedDict, cast

from .types import Nonprofit, OrganizationType


class Pub78Source(TypedDict, total=False):
    """IRS Publication 78 findings."""

    verified: bool | None
    organization_name: str | None
    ein: str | None
    city: str | None
    state: str | None
    indicator: str | None
    church_message: str | None
    source_org_type_1: str | None
    source_org_type_2: str | None
    source_org_type_3: str | None
    organization_types: list[OrganizationType] | None
    most_recent: str | None


class BmfSource(TypedDict, total=False):
    """IRS Business Master File findings."""

    status: bool | None
    organization_name: str | None
    ein: str | None
    city: str | None
    state: str | None
    street_address: str | None
    church_message: str | None
    subsection: str | None
    subsection_description: str | None
    foundation_code: str | None
    foundation_code_description: str | None
    foundation_type_code: str | None
    foundation_type_description: str | None
    foundation_509a_status: str | None
    ruling_month: str | None
    ruling_year: str | None
    group_exemption: str | None
    exempt_status_code: str | None
    filing_req_code: str | None
    pf_filing_req_cd: str | None
    deductability_text: str | None
    most_recent: str | None


class AroeSource(TypedDict, total=False):
    """IRS Automatic Revocation of Exemption findings."""

    revocation_code: str | None
    revocation_date: str | None
    reinstatement_date: str | None
    list_published_date: str | None


class OfacSource(TypedDict, total=False):
    """IRS OFAC Specially Designated Nationals findings."""

    status: str | None
    """
    The finding as the API phrases it. This is prose, not a flag; the API does
    not currently return a boolean match indicator, and this SDK does not invent
    one by matching on the wording.
    """

    list_published_date: str | None


_PUB78_FIELDS = {
    "verified": "pub78_verified",
    "organization_name": "pub78_organization_name",
    "ein": "pub78_ein",
    "city": "pub78_city",
    "state": "pub78_state",
    "indicator": "pub78_indicator",
    "church_message": "pub78_church_message",
    "source_org_type_1": "pub78_source_org_type_1",
    "source_org_type_2": "pub78_source_org_type_2",
    "source_org_type_3": "pub78_source_org_type_3",
    "organization_types": "organization_types",
    "most_recent": "most_recent_pub78",
}

_BMF_FIELDS = {
    "status": "bmf_status",
    "organization_name": "bmf_organization_name",
    "ein": "bmf_ein",
    "city": "bmf_city",
    "state": "bmf_state",
    "street_address": "bmf_street_address",
    "church_message": "bmf_church_message",
    "subsection": "bmf_subsection",
    "subsection_description": "subsection_description",
    "foundation_code": "foundation_code",
    "foundation_code_description": "foundation_code_description",
    "foundation_type_code": "foundation_type_code",
    "foundation_type_description": "foundation_type_description",
    "foundation_509a_status": "foundation_509a_status",
    "ruling_month": "ruling_month",
    "ruling_year": "ruling_year",
    "group_exemption": "group_exemption",
    "exempt_status_code": "exempt_status_code",
    "filing_req_code": "filing_req_code",
    "pf_filing_req_cd": "bmf_source_pf_filing_req_cd",
    "deductability_text": "bmf_deductability_text",
    "most_recent": "most_recent_bmf",
}

_AROE_FIELDS = {
    "revocation_code": "revocation_code",
    "revocation_date": "revocation_date",
    "reinstatement_date": "reinstatement_date",
    "list_published_date": "aroe_list_published_date",
}

_OFAC_FIELDS = {
    "status": "ofac_status",
    "list_published_date": "ofac_list_published_date",
}


def get_pub78(nonprofit: Nonprofit) -> Pub78Source | None:
    """Publication 78 findings, or ``None`` if the API returned none."""
    return cast("Pub78Source | None", _project(nonprofit, _PUB78_FIELDS))


def get_bmf(nonprofit: Nonprofit) -> BmfSource | None:
    """Business Master File findings, or ``None`` if the API returned none."""
    return cast("BmfSource | None", _project(nonprofit, _BMF_FIELDS))


def get_aroe(nonprofit: Nonprofit) -> AroeSource | None:
    """Automatic Revocation of Exemption findings, or ``None`` if the API returned none."""
    return cast("AroeSource | None", _project(nonprofit, _AROE_FIELDS))


def get_ofac(nonprofit: Nonprofit) -> OfacSource | None:
    """OFAC findings, or ``None`` if the API returned none."""
    return cast("OfacSource | None", _project(nonprofit, _OFAC_FIELDS))


def _project(nonprofit: Nonprofit, mapping: dict[str, str]) -> dict[str, Any] | None:
    """
    Copies the mapped fields onto a new dict, preserving ``None`` and ``False``.

    Returns ``None`` only when every mapped field is absent from the response,
    which is how "this source was not returned" is represented.
    """
    result: dict[str, Any] = {}
    record = cast(dict[str, Any], nonprofit)

    for target, wire_field in mapping.items():
        if wire_field in record:
            result[target] = record[wire_field]

    return result or None
