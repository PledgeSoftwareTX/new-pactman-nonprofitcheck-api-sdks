# frozen_string_literal: true

require_relative "test_helper"
require "contract"
require "fixtures"

# `scripts/contract.rb` decides what counts as the API having changed, and the
# live smoke test fails a run on its answer. The rules that are easy to get
# subtly wrong are the ones about absence: a field that is missing because it was
# removed, versus one that is missing because the object it lives in arrived
# null. Getting that backwards either fails every green run or passes every
# broken one, and neither is visible without a live deployment to try it
# against — so it is pinned here.
class CoverageDiffTest < Minitest::Test
  # The smallest expectation that still has a nested object and an array in it.
  EXPECTED = {
    "code" => "number",
    "data" => "null|object",
    "data.ein" => "digits:9",
    "data.organization_types" => "array|null",
    "data.organization_types[]" => "object",
    "data.organization_types[].organization_type" => "null|string",
    "errors" => "array|null|string",
    "errors[]" => "object",
    "errors[].reason" => "string"
  }.freeze

  # A successful response: no errors, and this organization has no types.
  SUCCESS = {
    "code" => "number",
    "data" => "object",
    "data.ein" => "digits:9",
    "data.organization_types" => "null",
    "errors" => "null"
  }.freeze

  def test_passes_a_response_whose_absent_paths_all_sit_under_a_null_parent
    result = Contract.coverage_diff(EXPECTED, SUCCESS)

    assert_empty result[:changes]
    assert_equal 0, result[:total]
    # errors[], errors[].reason, organization_types[] and its one field.
    assert_equal 4, result[:unreachable]
  end

  def test_fails_a_field_that_went_missing_while_its_parent_was_there
    result = Contract.coverage_diff(EXPECTED, SUCCESS.except("data.ein"))

    assert_equal [{ kind: :removed, path: "data.ein", token: "digits:9" }], result[:changes]
  end

  def test_fails_a_field_the_api_invented
    result = Contract.coverage_diff(EXPECTED, SUCCESS.merge("data.new_field" => "text"))

    assert_equal [{ kind: :added, path: "data.new_field", token: "text" }], result[:changes]
  end

  def test_reports_a_container_that_vanished_once_not_once_per_field_under_it
    result = Contract.coverage_diff(EXPECTED, { "code" => "number", "errors" => "null" })

    assert_equal [{ kind: :removed, path: "data", token: "null|object" }], result[:changes]
  end

  def test_treats_an_array_that_arrived_empty_as_having_no_room_for_its_elements
    assert_equal 0, Contract.coverage_diff(EXPECTED, SUCCESS.merge("data.organization_types" => "array"))[:total]
  end

  def test_fails_a_field_missing_from_the_elements_an_array_did_return
    observed = SUCCESS.merge("data.organization_types" => "array", "data.organization_types[]" => "object")

    assert_equal [{ kind: :removed, path: "data.organization_types[].organization_type", token: "null|string" }],
                 Contract.coverage_diff(EXPECTED, observed)[:changes]
  end

  def test_excuses_an_absent_field_the_models_declare_optional
    required = %w[data errors[]].to_set
    result = Contract.coverage_diff(EXPECTED, SUCCESS.except("data.ein"), required)

    assert_empty result[:changes]
    assert_equal 1, result[:optional_absent]
  end
end

class RecordedBaselineTest < Minitest::Test
  RECORDED = { "code" => "number", "data.ein" => "digits:9", "data.city" => "text" }.freeze

  def test_reports_a_path_that_appeared_and_a_path_that_disappeared
    now = { "code" => "number", "data.ein" => "digits:9", "data.county" => "text" }

    assert_equal [{ kind: :removed, path: "data.city", token: "text" },
                  { kind: :added, path: "data.county", token: "text" }],
                 Contract.schema_diff(RECORDED, now)[:changes]
  end

  def test_reports_a_value_whose_form_moved_on_a_path_both_have
    now = RECORDED.merge("data.ein" => "digits:2-7")

    assert_equal [{ kind: :changed, path: "data.ein", from: "digits:9", to: "digits:2-7" }],
                 Contract.type_diff(RECORDED, now)[:changes]
  end

  def test_sees_no_difference_in_an_identical_signature
    assert_equal 0, Contract.schema_diff(RECORDED, RECORDED.dup)[:total]
    assert_equal 0, Contract.type_diff(RECORDED, RECORDED.dup)[:total]
  end
end

class BaselineDiffTest < Minitest::Test
  # One organization, recorded on an afternoon its Pub 78 row was populated.
  RECORDED = {
    "code" => "number",
    "data.ein" => "digits:9",
    "data.pub78_city" => "text",
    "data.organization_types" => "array",
    "data.organization_types[]" => "object",
    "data.organization_types[].organization_type" => "text",
    "errors" => "null"
  }.freeze

  def test_passes_a_subject_whose_nullable_fields_came_back_empty_this_time
    now = { "code" => "number", "data.ein" => "digits:9", "data.pub78_city" => "null",
            "data.organization_types" => "null", "errors" => "null" }
    result = Contract.baseline_diff(RECORDED, now)

    assert_empty result[:changes]
    assert_equal 2, result[:nullable]
    # organization_types[] and the one field under it.
    assert_equal 2, result[:unreachable]
  end

  def test_passes_a_field_that_filled_in_since_the_recording
    result = Contract.baseline_diff({ "data.pub78_city" => "null" }, { "data.pub78_city" => "text" })

    assert_empty result[:changes]
    assert_equal 1, result[:nullable]
  end

  def test_passes_a_token_that_only_gained_or_lost_null
    result = Contract.baseline_diff({ "data[].address_line2" => "digits:4|null" },
                                    { "data[].address_line2" => "digits:4" })

    assert_empty result[:changes]
    assert_equal 1, result[:nullable]
  end

  def test_passes_the_paths_under_a_parent_that_was_null_when_it_was_recorded
    result = Contract.baseline_diff({ "errors" => "null" },
                                    { "errors" => "array", "errors[]" => "object", "errors[].code" => "number" })

    assert_empty result[:changes]
    assert_equal 2, result[:unreachable]
  end

  def test_still_fails_a_value_whose_form_moved_between_two_real_forms
    result = Contract.baseline_diff({ "data.ein" => "digits:9" }, { "data.ein" => "text" })

    assert_equal [{ kind: :changed, path: "data.ein", from: "digits:9", to: "text" }], result[:changes]
    assert_equal 0, result[:nullable]
  end

  def test_still_fails_a_form_that_moved_while_the_field_also_turned_nullable
    result = Contract.baseline_diff({ "data.ein" => "digits:9" }, { "data.ein" => "null|text" })

    assert_equal [{ kind: :changed, path: "data.ein", from: "digits:9", to: "null|text" }], result[:changes]
  end

  def test_still_fails_a_field_that_vanished_while_its_parent_was_there
    assert_equal [{ kind: :removed, path: "data.ein", token: "digits:9" }],
                 Contract.baseline_diff(RECORDED, RECORDED.except("data.ein"))[:changes]
  end

  def test_still_fails_a_field_the_api_invented
    assert_equal [{ kind: :added, path: "data.county", token: "text" }],
                 Contract.baseline_diff(RECORDED, RECORDED.merge("data.county" => "text"))[:changes]
  end
end

class ComposeExpectedTest < Minitest::Test
  def test_describes_the_record_under_data_for_single_and_under_data_array_for_bulk
    contract = {
      "envelope" => { "code" => "number", "errors" => "array|null|string" },
      "errorDetail" => { "reason" => "string" },
      "nonprofit" => { "ein" => "digits:9|null" },
      "organizationType" => { "organization_type" => "null|string" }
    }

    assert_equal "digits:9|null", Contract.compose_expected(contract, :single)["data.ein"]
    assert_equal "digits:9|null", Contract.compose_expected(contract, :bulk)["data[].ein"]
    assert_equal "null|object", Contract.compose_expected(contract, :single)["data"]
    assert_equal "array|null", Contract.compose_expected(contract, :bulk)["data"]
  end

  def test_lets_an_element_of_organization_types_be_null
    contract = { "envelope" => {}, "errorDetail" => {}, "nonprofit" => {},
                 "organizationType" => { "organization_type" => "null|string" } }

    assert_equal "null|object", Contract.compose_expected(contract, :single)["data.organization_types[]"]
    assert_equal "null|object", Contract.compose_expected(contract, :bulk)["data[].organization_types[]"]
  end
end

# The token vocabulary is shared with every other SDK in the repository, so a
# baseline recorded by one reads the same in all of them.
class SignatureTest < Minitest::Test
  def test_classifies_values_by_form_never_by_value
    {
      "411787097" => "digits:9",
      "01085-2643" => "digits:5-4",
      "00" => "digits:2",
      "3/25/2026 3:28:54 PM" => "date",
      "3/25/2026, 3:28:54 PM" => "date",
      "2026-03-25T15:28:54Z" => "date:iso",
      "https://pactman.org/profile/nonprofit/x" => "url",
      Fixtures::OFAC_NO_MATCH => "ofac-sentence",
      Fixtures::OFAC_POSSIBLE_MATCH => "ofac-sentence",
      "   " => "empty",
      "WESTFIELD" => "text"
    }.each { |value, token| assert_equal token, Contract.format_of(value), value }
  end

  def test_collapses_every_array_element_onto_one_path
    body = { "code" => 200,
             "data" => [{ "ein" => "411787097", "zip" => nil }, { "ein" => "996589560", "zip" => "01085" }],
             "errors" => nil }

    assert_equal({ "code" => "number", "data" => "array", "data[]" => "object", "data[].ein" => "digits:9",
                   "data[].zip" => "digits:5|null", "errors" => "null" }, Contract.signature_of(body))
  end

  def test_matches_the_committed_baseline_for_a_fixture_shaped_like_production
    baseline = JSON.parse(File.read(File.expand_path("../lib/pactman/nonprofit_check_plus/response_baseline.json",
                                                     __dir__)))
    record = Fixtures.organization(Fixtures::EINS[:public_charity])
    body = { "code" => 200, "message" => "OK", "errors" => nil, "data" => record, "timeTaken" => 3,
             "nonprofit_check_count" => 1 }

    # Same shape as production wherever the fixture has a value production had.
    assert_equal 0, Contract.baseline_diff(baseline.dig("single", "signature"), Contract.signature_of(body))[:total]
  end
end
