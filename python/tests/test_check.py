from __future__ import annotations

from typing import Any, cast

import pytest

from conftest import (
    BASE_URL,
    TEST_API_KEY,
    Stub,
    TransportMock,
    client_with,
    envelope,
    nonprofit_fixture,
)
from pactman_nonprofit_check_plus import MAX_BULK_EINS, PactmanValidationError
from pactman_nonprofit_check_plus.version import PACKAGE_NAME


class TestCheck:
    def test_sends_one_authenticated_request_and_returns_a_deserialized_model(self) -> None:
        mock = TransportMock([Stub(body=envelope(nonprofit_fixture()))])
        result = client_with(mock).nonprofits.check("411787097")

        assert len(mock.requests) == 1

        request = mock.requests[0]
        assert request.method == "GET"
        assert str(request.url) == f"{BASE_URL}/api/entities/nonprofitcheck/v1/us/ein/411787097"
        assert request.headers["authorization"] == f"Bearer {TEST_API_KEY}"
        assert request.headers["accept"] == "application/json"
        assert PACKAGE_NAME in request.headers["user-agent"]

        assert result.nonprofit is not None
        assert result.nonprofit["organization_name"] == "EXAMPLE NONPROFIT"
        assert result.nonprofit["ein"] == "411787097"

    def test_normalizes_a_hyphenated_ein_before_building_the_url(self) -> None:
        mock = TransportMock([Stub(body=envelope(nonprofit_fixture()))])
        client_with(mock).nonprofits.check("41-1787097")

        assert str(mock.requests[0].url).endswith("/us/ein/411787097")

    def test_maps_usage_information_from_the_envelope(self) -> None:
        mock = TransportMock(
            [Stub(body=envelope(nonprofit_fixture(), nonprofit_check_count=7, timeTaken=42))]
        )
        result = client_with(mock).nonprofits.check("411787097")

        assert result.check_count == 7
        assert result.time_taken_ms == 42
        assert result.status == 200

    def test_preserves_none_and_false_as_distinct_values(self) -> None:
        mock = TransportMock(
            [
                Stub(
                    body=envelope(
                        nonprofit_fixture(
                            pub78_verified=False,
                            bmf_status=None,
                            revocation_code=None,
                            irs_bmf_pub78_conflict=False,
                        )
                    )
                )
            ]
        )
        nonprofit = client_with(mock).nonprofits.check("411787097").nonprofit

        assert nonprofit is not None
        assert nonprofit["pub78_verified"] is False
        assert nonprofit["bmf_status"] is None
        assert nonprofit["revocation_code"] is None
        assert nonprofit["irs_bmf_pub78_conflict"] is False
        assert "NOT included" in (nonprofit["ofac_status"] or "")

    def test_keeps_unknown_future_fields_readable_through_the_raw_response(self) -> None:
        mock = TransportMock(
            [
                Stub(
                    body={
                        **envelope(nonprofit_fixture(future_source_status="listed")),
                        "future_envelope_field": {"nested": True},
                    }
                )
            ]
        )
        result = client_with(mock).nonprofits.check("411787097")

        assert result.nonprofit is not None
        assert result.nonprofit["organization_name"] == "EXAMPLE NONPROFIT"

        # Fields a newer API version added are readable through a dict view; the
        # TypedDict only describes what this SDK release knows about.
        record = cast(dict[str, Any], result.nonprofit)
        assert record["future_source_status"] == "listed"

        assert isinstance(result.raw, dict)
        assert cast(dict[str, Any], result.raw)["future_envelope_field"] == {"nested": True}

    def test_returns_none_rather_than_raising_when_data_is_absent(self) -> None:
        mock = TransportMock([Stub(body=envelope(None, nonprofit_check_count=0))])
        result = client_with(mock).nonprofits.check("411787097")

        assert result.nonprofit is None
        assert result.check_count == 0

    def test_fails_locally_on_a_malformed_ein_without_sending_a_request(self) -> None:
        mock = TransportMock([Stub(body=envelope(nonprofit_fixture()))])

        with pytest.raises(PactmanValidationError):
            client_with(mock).nonprofits.check("41178709")

        assert mock.requests == []


class TestCheckBulk:
    def test_sends_one_request_with_a_bare_json_array_of_normalized_eins(self) -> None:
        mock = TransportMock(
            [Stub(body=envelope([nonprofit_fixture(), nonprofit_fixture(ein="996589560")]))]
        )
        result = client_with(mock).nonprofits.check_bulk(["41-1787097", "996589560"])

        assert len(mock.requests) == 1

        request = mock.requests[0]
        assert request.method == "POST"
        assert str(request.url) == f"{BASE_URL}/api/entities/nonprofitcheckbulk/v1/us/eins"
        assert request.headers["content-type"] == "application/json"
        assert mock.json_body() == ["411787097", "996589560"]

        assert len(result.organizations) == 2
        assert result.organizations[1]["ein"] == "996589560"

    def test_preserves_input_order_and_duplicates_by_default(self) -> None:
        mock = TransportMock([Stub(body=envelope([]))])
        client_with(mock).nonprofits.check_bulk(["996589560", "41-1787097", "996589560"])

        assert mock.json_body() == ["996589560", "411787097", "996589560"]

    def test_removes_duplicates_only_when_dedupe_is_requested(self) -> None:
        mock = TransportMock([Stub(body=envelope([]))])
        client_with(mock).nonprofits.check_bulk(
            ["996589560", "996589560", "41-1787097"], dedupe=True
        )

        assert mock.json_body() == ["996589560", "411787097"]

    def test_rejects_an_empty_collection_locally(self) -> None:
        mock = TransportMock([Stub(body=envelope([]))])

        with pytest.raises(PactmanValidationError):
            client_with(mock).nonprofits.check_bulk([])

        assert mock.requests == []

    def test_rejects_the_whole_batch_when_one_ein_is_malformed_before_sending(self) -> None:
        mock = TransportMock([Stub(body=envelope([]))])

        with pytest.raises(PactmanValidationError) as excinfo:
            client_with(mock).nonprofits.check_bulk(["411787097", "not-an-ein"])

        assert excinfo.value.issues[0].index == 1
        assert mock.requests == []

    def test_enforces_the_server_batch_limit_locally_from_a_single_constant(self) -> None:
        mock = TransportMock([Stub(body=envelope([]))])

        with pytest.raises(PactmanValidationError, match=f"at most {MAX_BULK_EINS} EINs"):
            client_with(mock).nonprofits.check_bulk(["411787097"] * (MAX_BULK_EINS + 1))

        assert mock.requests == []

    def test_accepts_exactly_the_batch_limit(self) -> None:
        mock = TransportMock([Stub(body=envelope([]))])
        client_with(mock).nonprofits.check_bulk(["411787097"] * MAX_BULK_EINS)

        assert len(mock.requests) == 1

    def test_surfaces_per_item_not_found_results_from_a_successful_response(self) -> None:
        mock = TransportMock(
            [
                Stub(
                    status=200,
                    body=envelope(
                        [nonprofit_fixture()],
                        nonprofit_check_count=1,
                        errors=[
                            {
                                "resource": "nonprofitcheckbulk",
                                "reason": "There are no matching nonprofits in our records for this set of EINs",
                                "code": 404,
                                "eins": ["996589560"],
                            }
                        ],
                    ),
                )
            ]
        )
        result = client_with(mock).nonprofits.check_bulk(["411787097", "996589560"])

        assert len(result.organizations) == 1
        assert result.not_found_eins == ["996589560"]
        assert result.errors[0]["code"] == 404
        assert result.check_count == 1

    def test_reads_organizations_from_a_wrapped_data_object_as_well_as_a_bare_array(
        self,
    ) -> None:
        mock = TransportMock(
            [Stub(body=envelope({"organizations": [nonprofit_fixture()]}))]
        )
        result = client_with(mock).nonprofits.check_bulk(["411787097"])

        assert len(result.organizations) == 1

    def test_rejects_a_bare_string_locally_rather_than_iterating_its_characters(self) -> None:
        mock = TransportMock([Stub(body=envelope([]))])

        with pytest.raises(PactmanValidationError, match="use check\\(\\) for a single EIN"):
            client_with(mock).nonprofits.check_bulk("411787097")

        assert mock.requests == []

    def test_collects_comma_separated_not_found_eins(self) -> None:
        mock = TransportMock(
            [
                Stub(
                    body=envelope(
                        [],
                        errors=[{"reason": "no records", "eins": "996589560, 411787097"}],
                    )
                )
            ]
        )
        result = client_with(mock).nonprofits.check_bulk(["996589560", "411787097"])

        assert result.not_found_eins == ["996589560", "411787097"]
