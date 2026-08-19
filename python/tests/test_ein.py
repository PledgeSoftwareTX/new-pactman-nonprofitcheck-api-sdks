from __future__ import annotations

import pytest

from pactman_nonprofit_check_plus import (
    PactmanValidationError,
    is_valid_ein,
    normalize_ein,
    normalize_eins,
)


class TestNormalizeEin:
    def test_normalizes_hyphenated_and_bare_eins_to_the_same_value(self) -> None:
        assert normalize_ein("41-1787097") == "411787097"
        assert normalize_ein("411787097") == "411787097"

    def test_ignores_surrounding_whitespace(self) -> None:
        assert normalize_ein("  41-1787097  ") == "411787097"

    @pytest.mark.parametrize(
        "value",
        ["", "   ", "4117870", "4117870971", "41-178709", "abcdefghi", "41_1787097", None, 411787097],
    )
    def test_rejects_values_that_are_not_shaped_like_an_ein(self, value: object) -> None:
        with pytest.raises(PactmanValidationError):
            normalize_ein(value)

    def test_names_the_offending_value_without_leaking_configuration(self) -> None:
        with pytest.raises(PactmanValidationError) as excinfo:
            normalize_ein("not-an-ein")

        error = excinfo.value
        assert "not-an-ein" in error.message
        assert error.issues[0].value == "not-an-ein"
        assert error.issues[0].index is None

    def test_reports_the_received_type_for_a_non_string(self) -> None:
        with pytest.raises(PactmanValidationError, match="received int"):
            normalize_ein(411787097)


class TestNormalizeEins:
    def test_preserves_order_and_duplicates(self) -> None:
        assert normalize_eins(["99-6589560", "411787097", "996589560"]) == [
            "996589560",
            "411787097",
            "996589560",
        ]

    def test_identifies_which_item_failed_by_index_and_value(self) -> None:
        with pytest.raises(PactmanValidationError) as excinfo:
            normalize_eins(["411787097", "nope", "996589560", ""])

        issues = excinfo.value.issues
        assert [issue.index for issue in issues] == [1, 3]
        assert [issue.value for issue in issues] == ["nope", ""]
        assert "2 of 4 EINs are invalid" in excinfo.value.message

    def test_accepts_an_empty_collection_without_raising(self) -> None:
        assert normalize_eins([]) == []


class TestIsValidEin:
    @pytest.mark.parametrize("value", ["411787097", "41-1787097", " 411787097 "])
    def test_accepts_well_formed_eins(self, value: str) -> None:
        assert is_valid_ein(value) is True

    @pytest.mark.parametrize("value", ["", "4117870", None, 411787097, ["411787097"]])
    def test_rejects_anything_else_without_raising(self, value: object) -> None:
        assert is_valid_ein(value) is False
