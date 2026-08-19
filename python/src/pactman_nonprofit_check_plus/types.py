"""
Response models.

Field names mirror the wire format exactly, so what you read in the Pactman API
reference is what you access in code — no rename table to keep in sync.

Wire models are :class:`~typing.TypedDict` definitions with ``total=False``:
every field is optional, because the API omits fields it has no data for. They
are plain ``dict`` objects at runtime, so fields added by a future API version
stay readable through ``nonprofit.get("new_field")`` without a deserialization
failure or an SDK upgrade.

Results returned by the client are frozen dataclasses, since those are shapes
this SDK defines rather than shapes the wire dictates.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, TypedDict


class OrganizationType(TypedDict, total=False):
    """A deductibility entry from IRS Publication 78."""

    organization_type: str | None
    deductibility_limitation: str | None
    deductibility_status_description: str | None


class Nonprofit(TypedDict, total=False):
    """
    A nonprofit record as returned by the US nonprofit check endpoints.

    Source-specific findings are flat on this object, prefixed by source
    (``pub78_*``, ``bmf_*``, ``ofac_*``, and the revocation fields for the IRS
    Automatic Revocation of Exemption list). See :mod:`.sources` for grouped
    views.
    """

    # Pactman
    pactman_org_url: str | None
    organization_info_last_modified: str | None

    # Identity and address
    ein: str | None
    organization_name: str | None
    organization_name_aka: str | None
    address_line1: str | None
    address_line2: str | None
    city: str | None
    state: str | None
    state_name: str | None
    zip: str | None
    filing_req_code: str | None

    # IRS Publication 78
    pub78_church_message: str | None
    pub78_organization_name: str | None
    pub78_ein: str | None
    pub78_verified: bool | None
    pub78_city: str | None
    pub78_state: str | None
    pub78_indicator: str | None
    pub78_source_org_type_1: str | None
    pub78_source_org_type_2: str | None
    pub78_source_org_type_3: str | None
    organization_types: list[OrganizationType] | None
    most_recent_pub78: str | None

    # IRS Business Master File
    bmf_church_message: str | None
    bmf_organization_name: str | None
    bmf_ein: str | None
    bmf_status: bool | None
    bmf_city: str | None
    bmf_state: str | None
    bmf_street_address: str | None
    bmf_subsection: str | None
    bmf_source_pf_filing_req_cd: str | None
    bmf_deductability_text: str | None
    most_recent_bmf: str | None
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

    # OFAC Specially Designated Nationals.
    #
    # The API returns a sentence, not a flag — do not pattern-match it to derive
    # a boolean. Read it, or present it to a reviewer.
    ofac_status: str | None
    ofac_list_published_date: str | None

    # IRS Automatic Revocation of Exemption
    revocation_code: str | None
    revocation_date: str | None
    reinstatement_date: str | None
    aroe_list_published_date: str | None

    # True when the IRS BMF and Publication 78 records disagree.
    irs_bmf_pub78_conflict: bool | None
    report_date: str | None


class ApiErrorDetail(TypedDict, total=False):
    """One entry from the envelope's ``errors`` array."""

    resource: str
    """The API resource the error came from."""

    reason: str
    """Human-readable explanation."""

    code: int
    """Status code for this specific failure, which may differ from the HTTP status."""

    eins: list[str] | str
    """EINs this error applies to, for bulk requests."""


class ApiEnvelope(TypedDict, total=False):
    """The envelope every nonprofit check response is wrapped in."""

    code: int
    message: str

    errors: list[ApiErrorDetail] | str | None
    """
    Item-level failures. Present on successful responses too — a bulk request
    where some EINs were not found returns HTTP 200 with entries here.
    """

    data: Any

    timeTaken: float | None
    """Server-side processing time in milliseconds."""

    nonprofit_check_count: int | None
    """
    Checks the account has consumed so far in the current billing cycle,
    including this request. It resets when a new cycle begins.

    This is a running total, not the size of the request you just made. To learn
    what one request cost, compare this value across two responses.
    """


@dataclass(frozen=True)
class PactmanResult:
    """Fields shared by every result this SDK returns."""

    check_count: int | None
    """
    ``nonprofit_check_count`` from the envelope: checks consumed so far in the
    current billing cycle, including this request, resetting each cycle.

    Not the size of this request. Take the delta between two responses if you
    need that, and read this one as a usage gauge.
    """

    time_taken_ms: float | None
    """Server-side processing time in milliseconds, when reported."""

    errors: list[ApiErrorDetail]
    """
    Item-level failures reported alongside a successful response. Empty when the
    API reported none.
    """

    request_id: str | None
    """Correlation identifier from the response headers, when the server sent one."""

    status: int
    """HTTP status of the response."""

    raw: ApiEnvelope | str | None
    """
    The unmodified parsed response body, including any fields not typed above.

    Normally the parsed envelope. A server that answers 200 with a non-JSON body
    leaves the raw text here rather than discarding the evidence.
    """


@dataclass(frozen=True)
class SingleCheckResult(PactmanResult):
    """The result of :meth:`.NonprofitsResource.check`."""

    nonprofit: Nonprofit | None
    """The organization, or ``None`` when the API returned no record."""


@dataclass(frozen=True)
class BulkCheckResult(PactmanResult):
    """The result of :meth:`.NonprofitsResource.check_bulk`."""

    organizations: list[Nonprofit]
    """
    Organizations the API matched, in the order it returned them — which is not
    guaranteed to follow the order you supplied. Index by ``ein``.
    """

    not_found_eins: list[str]
    """
    EINs the API reported no record for, collected from ``errors``.

    A bulk request where some EINs miss is a successful HTTP 200, not an error.
    """
