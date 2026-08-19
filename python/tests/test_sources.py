from __future__ import annotations

from typing import Any

from conftest import nonprofit_fixture
from pactman_nonprofit_check_plus import Nonprofit, get_aroe, get_bmf, get_ofac, get_pub78


def fixture(**overrides: Any) -> Nonprofit:
    return nonprofit_fixture(**overrides)  # type: ignore[return-value]


class TestSourceProjections:
    def test_maps_publication_78_fields_from_the_response(self) -> None:
        pub78 = get_pub78(fixture())

        assert pub78 is not None
        assert pub78["verified"] is True
        assert pub78["organization_name"] == "Example Nonprofit"
        assert pub78["ein"] == "411787097"
        assert pub78["city"] == "Westfield"
        assert pub78["state"] == "MA"
        assert pub78["indicator"] == "0"
        assert pub78["most_recent"] == "12/12/2025 12:00:00 AM"
        assert pub78["organization_types"][0]["deductibility_limitation"] == "50%"  # type: ignore[index]

    def test_maps_business_master_file_fields_from_the_response(self) -> None:
        bmf = get_bmf(fixture())

        assert bmf is not None
        assert bmf["status"] is True
        assert bmf["organization_name"] == "EXAMPLE NONPROFIT"
        assert bmf["subsection"] == "03"
        assert bmf["subsection_description"] == "501(c)(3) Public Charity"
        assert bmf["foundation_code"] == "10"
        assert bmf["ruling_year"] == "2024"
        assert bmf["most_recent"] == "12/09/2025 12:00:00 AM"

    def test_renames_only_where_the_wire_prefix_differs(self) -> None:
        bmf = get_bmf(
            fixture(bmf_source_pf_filing_req_cd="0", bmf_deductability_text="Contributions are deductible")
        )

        assert bmf is not None
        assert bmf["pf_filing_req_cd"] == "0"
        assert bmf["deductability_text"] == "Contributions are deductible"

    def test_maps_automatic_revocation_fields_from_the_response(self) -> None:
        aroe = get_aroe(
            fixture(
                revocation_code="1",
                revocation_date="5/15/2020",
                reinstatement_date="8/1/2021",
                aroe_list_published_date="12/10/2025",
            )
        )

        assert aroe is not None
        assert aroe["revocation_code"] == "1"
        assert aroe["revocation_date"] == "5/15/2020"
        assert aroe["reinstatement_date"] == "8/1/2021"
        assert aroe["list_published_date"] == "12/10/2025"

    def test_maps_ofac_fields_verbatim_without_deriving_a_boolean(self) -> None:
        ofac = get_ofac(fixture())

        assert ofac is not None
        assert isinstance(ofac["status"], str)
        assert "NOT included" in ofac["status"]
        # The projection must not invent a match flag from the wording.
        assert set(ofac) <= {"status", "list_published_date"}

    def test_keeps_a_missing_source_distinct_from_an_explicit_negative(self) -> None:
        empty: Nonprofit = {"ein": "411787097"}

        assert get_pub78(empty) is None
        assert get_bmf(empty) is None
        assert get_aroe(empty) is None
        assert get_ofac(empty) is None

        negative = get_pub78({"pub78_verified": False})
        assert negative is not None
        assert negative["verified"] is False

        explicit_null = get_ofac({"ofac_status": None})
        assert explicit_null is not None
        assert explicit_null["status"] is None

    def test_reports_a_source_as_present_when_only_some_fields_were_returned(self) -> None:
        bmf = get_bmf({"bmf_status": True})

        assert bmf is not None
        assert bmf == {"status": True}

    def test_never_produces_a_composite_verdict_field(self) -> None:
        forbidden = {"approved", "eligible", "safe", "verdict", "is_valid", "passed"}

        for projection in (get_pub78, get_bmf, get_aroe, get_ofac):
            result = projection(fixture())
            assert result is not None
            assert forbidden.isdisjoint(result)
