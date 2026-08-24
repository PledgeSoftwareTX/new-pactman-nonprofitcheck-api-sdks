"""
``scripts/contract.py`` decides what counts as the API having changed, and the
live smoke test fails a run on its answer. The rules that are easy to get subtly
wrong are the ones about absence: a field that is missing because it was removed,
versus one that is missing because the object it lives in arrived null. Getting
that backwards either fails every green run or passes every broken one, and
neither is visible without a live deployment to try it against — so it is pinned
here.
"""

from __future__ import annotations

from typing import ClassVar

from contract import (
    Change,
    baseline_diff,
    compose_expected,
    coverage_diff,
    schema_diff,
    type_diff,
)

# The smallest expectation that still has a nested object and an array in it.
EXPECTED: dict[str, str] = {
    "code": "number",
    "data": "null|object",
    "data.ein": "digits:9",
    "data.organization_types": "array|null",
    "data.organization_types[]": "object",
    "data.organization_types[].organization_type": "null|string",
    "errors": "array|null|string",
    "errors[]": "object",
    "errors[].reason": "string",
}

# A successful response: no errors, and this organization has no types.
SUCCESS: dict[str, str] = {
    "code": "number",
    "data": "object",
    "data.ein": "digits:9",
    "data.organization_types": "null",
    "errors": "null",
}


class TestCoverageDiff:
    def test_passes_a_response_whose_absent_paths_sit_under_a_null_parent(self) -> None:
        result = coverage_diff(EXPECTED, SUCCESS)

        assert result.changes == []
        assert result.total == 0
        # errors[], errors[].reason, organization_types[] and its one field.
        assert result.unreachable == 4

    def test_fails_a_field_that_went_missing_while_its_parent_was_there(self) -> None:
        without_ein = {path: token for path, token in SUCCESS.items() if path != "data.ein"}

        result = coverage_diff(EXPECTED, without_ein)

        assert result.total == 1
        assert result.changes == [Change(kind="removed", path="data.ein", token="digits:9")]

    def test_fails_a_field_the_api_invented(self) -> None:
        result = coverage_diff(EXPECTED, {**SUCCESS, "data.new_field": "text"})

        assert result.changes == [Change(kind="added", path="data.new_field", token="text")]

    def test_reports_a_vanished_container_once_not_once_per_field_under_it(self) -> None:
        result = coverage_diff(EXPECTED, {"code": "number", "errors": "null"})

        assert result.changes == [Change(kind="removed", path="data", token="null|object")]

    def test_treats_an_empty_array_as_having_no_room_for_its_elements(self) -> None:
        result = coverage_diff(EXPECTED, {**SUCCESS, "data.organization_types": "array"})

        assert result.total == 0

    def test_fails_a_field_missing_from_the_elements_an_array_did_return(self) -> None:
        result = coverage_diff(
            EXPECTED,
            {
                **SUCCESS,
                "data.organization_types": "array",
                "data.organization_types[]": "object",
            },
        )

        assert result.changes == [
            Change(
                kind="removed",
                path="data.organization_types[].organization_type",
                token="null|string",
            )
        ]


class TestTheRecordedBaseline:
    RECORDED: ClassVar[dict[str, str]] = {
        "code": "number",
        "data.ein": "digits:9",
        "data.city": "text",
    }

    def test_reports_a_path_that_appeared_and_a_path_that_disappeared(self) -> None:
        now = {"code": "number", "data.ein": "digits:9", "data.county": "text"}

        assert schema_diff(self.RECORDED, now).changes == [
            Change(kind="removed", path="data.city", token="text"),
            Change(kind="added", path="data.county", token="text"),
        ]

    def test_reports_a_value_whose_form_moved_on_a_path_both_have(self) -> None:
        now = {**self.RECORDED, "data.ein": "digits:2-7"}

        assert type_diff(self.RECORDED, now).changes == [
            Change(
                kind="changed", path="data.ein", from_token="digits:9", to_token="digits:2-7"
            )
        ]

    def test_sees_no_difference_in_an_identical_signature(self) -> None:
        assert schema_diff(self.RECORDED, dict(self.RECORDED)).total == 0
        assert type_diff(self.RECORDED, dict(self.RECORDED)).total == 0


class TestBaselineDiff:
    # One organization, recorded on an afternoon its Pub 78 row was populated.
    RECORDED: ClassVar[dict[str, str]] = {
        "code": "number",
        "data.ein": "digits:9",
        "data.pub78_city": "text",
        "data.organization_types": "array",
        "data.organization_types[]": "object",
        "data.organization_types[].organization_type": "text",
        "errors": "null",
    }

    def test_passes_a_subject_whose_nullable_fields_came_back_empty(self) -> None:
        now = {
            "code": "number",
            "data.ein": "digits:9",
            "data.pub78_city": "null",
            "data.organization_types": "null",
            "errors": "null",
        }

        result = baseline_diff(self.RECORDED, now)

        assert result.changes == []
        assert result.nullable == 2
        # organization_types[] and the one field under it.
        assert result.unreachable == 2

    def test_passes_a_field_that_filled_in_since_the_recording(self) -> None:
        result = baseline_diff({"data.pub78_city": "null"}, {"data.pub78_city": "text"})

        assert result.changes == []
        assert result.nullable == 1

    def test_passes_a_token_that_only_gained_or_lost_null(self) -> None:
        result = baseline_diff(
            {"data[].address_line2": "digits:4|null"},
            {"data[].address_line2": "digits:4"},
        )

        assert result.changes == []
        assert result.nullable == 1

    def test_passes_paths_under_a_parent_that_was_null_when_recorded(self) -> None:
        result = baseline_diff(
            {"errors": "null"},
            {"errors": "array", "errors[]": "object", "errors[].code": "number"},
        )

        assert result.changes == []
        assert result.unreachable == 2

    def test_still_fails_a_value_whose_form_moved_between_two_real_forms(self) -> None:
        result = baseline_diff({"data.ein": "digits:9"}, {"data.ein": "text"})

        assert result.changes == [
            Change(kind="changed", path="data.ein", from_token="digits:9", to_token="text")
        ]
        assert result.nullable == 0

    def test_still_fails_a_form_that_moved_while_also_turning_nullable(self) -> None:
        result = baseline_diff({"data.ein": "digits:9"}, {"data.ein": "null|text"})

        assert result.changes == [
            Change(
                kind="changed", path="data.ein", from_token="digits:9", to_token="null|text"
            )
        ]

    def test_still_fails_a_field_that_vanished_while_its_parent_was_there(self) -> None:
        now = dict(self.RECORDED)

        del now["data.ein"]

        assert baseline_diff(self.RECORDED, now).changes == [
            Change(kind="removed", path="data.ein", token="digits:9")
        ]

    def test_still_fails_a_field_the_api_invented(self) -> None:
        result = baseline_diff(self.RECORDED, {**self.RECORDED, "data.county": "text"})

        assert result.changes == [Change(kind="added", path="data.county", token="text")]


class TestComposeExpected:
    CONTRACT: ClassVar[dict[str, dict[str, str]]] = {
        "envelope": {"code": "number", "errors": "array|null|string"},
        "errorDetail": {"reason": "string"},
        "nonprofit": {"ein": "digits:9|null"},
        "organizationType": {"organization_type": "null|string"},
    }

    def test_describes_the_record_under_data_for_single_and_data_for_bulk(self) -> None:
        assert compose_expected(self.CONTRACT, "single")["data.ein"] == "digits:9|null"
        assert compose_expected(self.CONTRACT, "bulk")["data[].ein"] == "digits:9|null"
        assert compose_expected(self.CONTRACT, "single")["data"] == "null|object"
        assert compose_expected(self.CONTRACT, "bulk")["data"] == "array|null"

    def test_lets_an_element_of_organization_types_be_null(self) -> None:
        single = compose_expected(self.CONTRACT, "single")
        bulk = compose_expected(self.CONTRACT, "bulk")

        assert single["data.organization_types[]"] == "null|object"
        assert bulk["data[].organization_types[]"] == "null|object"
