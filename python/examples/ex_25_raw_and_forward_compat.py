"""
EX-25 — Raw response and forward compatibility.

The typed model and the raw envelope are both available, and the raw one is not
a debugging afterthought. When the API adds a field, the SDK you have installed
keeps working and the new field is readable immediately — no upgrade, no
deserialization failure, no dropped data.

The fixture used here is an approved response from a newer API version. It
carries fields this SDK has never heard of and an enum value outside the
documented set.

Run:  PACTMAN_API_KEY=... python examples/ex_25_raw_and_forward_compat.py
"""

from __future__ import annotations

import json
from typing import Any, cast

from lib.fixture_api import FIXTURE_EINS, KNOWN_NONPROFIT_FIELDS, fixture_api
from lib.print import bullet, field, heading, note, pick

from pactman_nonprofit_check_plus import get_bmf, get_pub78

KNOWN_FOUNDATION_TYPES = {"pc", "pf", "po"}
"""Documented foundation types. Anything else is unknown, not wrong."""


def main() -> int:
    with fixture_api() as client:
        result = client.nonprofits.check(FIXTURE_EINS["future_fields"])

    nonprofit = result.nonprofit

    if nonprofit is None:
        print("No record returned.")
        return 0

    bmf = get_bmf(nonprofit)
    pub78 = get_pub78(nonprofit)

    # Known fields deserialize exactly as they always have.
    heading("Known fields are unaffected")
    field("ein", pick(nonprofit, "ein"))
    field("organization_name", pick(nonprofit, "organization_name"))
    field("bmf_status", pick(bmf, "status"))
    field("pub78_verified", pick(pub78, "verified"))
    field("subsection_description", pick(bmf, "subsection_description"))

    # Unknown fields ride along on the same dict. No cast, no upgrade.
    record = cast(dict[str, Any], nonprofit)
    unknown_fields = [key for key in record if key not in KNOWN_NONPROFIT_FIELDS]

    heading("Fields this SDK version does not declare")
    field("count", len(unknown_fields))

    for key in unknown_fields:
        bullet(f"{key} = {json.dumps(record[key])}")

    # Under a strict type checker the TypedDict only describes what this release
    # knows about, so reach unknown keys through a dict view and narrow them
    # deliberately:
    #
    #   status = cast(dict[str, Any], nonprofit).get("state_charity_registration_status")
    #   if isinstance(status, str): ...
    registration = record.get("state_charity_registration_status")

    field(
        "read via a dict view",
        registration if isinstance(registration, str) else "<not a string>",
    )

    # An unknown value in a known field. This is the one that breaks applications
    # that map eagerly into an enum and default the miss.
    heading("An unrecognized value in a documented field")

    foundation_type = pick(bmf, "foundation_type_code")

    field("foundation_type_code", foundation_type)
    field("in the documented set", foundation_type in KNOWN_FOUNDATION_TYPES)
    field("foundation_type_description", pick(bmf, "foundation_type_description"))
    field(
        "handled as",
        "a known classification"
        if foundation_type in KNOWN_FOUNDATION_TYPES
        else "unknown — routed to review, not defaulted to a known type",
    )

    # Nested objects keep their unknown members too.
    types = pick(pub78, "organization_types")
    first_type = types[0] if isinstance(types, list) and types else None

    heading("Unknown members inside a known object")
    field("deductibility_limitation", pick(first_type, "deductibility_limitation"))
    field(
        "deductibility_status_description",
        pick(first_type, "deductibility_status_description"),
    )
    field("future_deductibility_note", pick(first_type, "future_deductibility_note"))

    # And the whole envelope, byte for byte as parsed.
    raw = cast(dict[str, Any], result.raw) if isinstance(result.raw, dict) else {}

    heading("The raw envelope")
    field("raw['code']", pick(raw, "code"))
    field("raw['message']", pick(raw, "message"))
    field("raw['timeTaken']", pick(raw, "timeTaken"))
    field("raw['nonprofit_check_count']", pick(raw, "nonprofit_check_count"))
    field("raw['data'] is the record", raw.get("data") is nonprofit)
    field("top-level envelope keys", ", ".join(raw))

    bullet("Persist `raw` when you need to prove later what the API actually said.")
    bullet("It is the parsed body, unmodified — nothing was dropped on the way through.")

    note(
        "Forward compatibility cuts both ways: an unknown value must never be coerced\n"
        'into a known one. "I do not recognize this" is a valid, and usually safer,\n'
        "outcome than a confident wrong answer."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
