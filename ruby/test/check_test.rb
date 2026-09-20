# frozen_string_literal: true

require_relative "test_helper"

class CheckTest < Minitest::Test
  include TestSupport

  def test_sends_exactly_one_authenticated_request_and_returns_a_model
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture) }])
    result = client_with(adapter).nonprofits.check("411787097")

    assert_equal 1, adapter.requests.size

    request = adapter.requests.first

    assert_equal :get, request.http_method
    assert_equal "#{BASE_URL}/api/entities/nonprofitcheck/v1/us/ein/411787097", request.url
    assert_equal "Bearer #{TEST_API_KEY}", request.headers["authorization"]
    assert_equal "application/json", request.headers["accept"]
    assert_includes request.headers["user-agent"], NCP::GEM_NAME
    assert_nil request.body

    assert_instance_of NCP::Nonprofit, result.nonprofit
    assert_equal "EXAMPLE NONPROFIT", result.nonprofit.organization_name
    assert_equal "411787097", result.nonprofit.ein
  end

  def test_normalizes_a_hyphenated_ein_before_building_the_url
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture) }])
    client_with(adapter).nonprofits.check("41-1787097")

    assert_match %r{/us/ein/411787097\z}, adapter.requests.first.url
  end

  def test_maps_usage_information_from_the_envelope
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture, "nonprofit_check_count" => 7, "timeTaken" => 42) }])
    result = client_with(adapter).nonprofits.check("411787097")

    assert_equal 7, result.check_count
    assert_equal 42, result.time_taken_ms
    assert_equal 200, result.status
  end

  def test_exposes_source_findings_and_keeps_nil_and_false_distinct
    record = nonprofit_fixture("pub78_verified" => false, "bmf_status" => nil, "irs_bmf_pub78_conflict" => false)
    adapter = FakeAdapter.new([{ body: envelope(record) }])
    nonprofit = client_with(adapter).nonprofits.check("411787097").nonprofit

    assert_equal false, nonprofit.pub78_verified
    assert_nil nonprofit.bmf_status
    assert_nil nonprofit.revocation_code
    assert nonprofit.key?(:revocation_code), "a null field is still a returned field"
    assert_equal false, nonprofit.irs_bmf_pub78_conflict
    assert_includes nonprofit.ofac_status, "NOT included"
  end

  def test_keeps_unknown_future_fields_readable
    body = envelope(nonprofit_fixture("future_source_status" => "listed"))
           .merge("future_envelope_field" => { "nested" => true })
    adapter = FakeAdapter.new([{ body: body }])
    result = client_with(adapter).nonprofits.check("411787097")

    assert_equal "EXAMPLE NONPROFIT", result.nonprofit.organization_name
    assert_equal "listed", result.nonprofit["future_source_status"]
    assert_equal "listed", result.nonprofit[:future_source_status]
    assert_equal({ "nested" => true }, result.raw["future_envelope_field"])
  end

  def test_the_model_reads_the_raw_body_rather_than_a_copy
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture) }])
    result = client_with(adapter).nonprofits.check("411787097")

    assert_same result.raw["data"], result.nonprofit.to_h
  end

  def test_wraps_organization_types_and_keeps_null_entries
    record = nonprofit_fixture("organization_types" => [{ "deductibility_limitation" => "50%" }, nil])
    adapter = FakeAdapter.new([{ body: envelope(record) }])
    types = client_with(adapter).nonprofits.check("411787097").nonprofit.organization_types

    assert_instance_of NCP::OrganizationType, types.first
    assert_equal "50%", types.first.deductibility_limitation
    assert_nil types.last
  end

  def test_returns_nil_rather_than_raising_when_data_is_absent
    adapter = FakeAdapter.new([{ body: envelope(nil, "nonprofit_check_count" => 0) }])
    result = client_with(adapter).nonprofits.check("411787097")

    assert_nil result.nonprofit
    assert_equal 0, result.check_count
  end

  def test_reports_nothing_rather_than_crashing_on_a_success_that_is_not_json
    adapter = FakeAdapter.new([{ status: 200, body_text: "OK" }])
    result = client_with(adapter).nonprofits.check("411787097")

    assert_nil result.nonprofit
    assert_nil result.check_count
    assert_equal "OK", result.raw
  end

  def test_fails_locally_on_a_malformed_ein_without_sending_a_request
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture) }])

    assert_raises(NCP::ValidationError) { client_with(adapter).nonprofits.check("41178709") }
    assert_empty adapter.requests
  end

  def test_rejects_an_unknown_keyword
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture) }])

    error = assert_raises(ArgumentError) { client_with(adapter).nonprofits.check("411787097", timeout_ms: 5) }

    assert_includes error.message, "timeout_ms"
    assert_empty adapter.requests
  end

  def test_sends_per_request_headers_without_letting_them_replace_the_credential
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture) }])
    client = client_with(adapter, default_headers: { "X-Team" => "grants", "AUTHORIZATION" => "Bearer stolen" })

    client.nonprofits.check("411787097", headers: { "X-Trace" => "t-1", "authorization" => "Basic nope" })

    headers = adapter.requests.first.headers

    assert_equal "grants", headers["x-team"]
    assert_equal "t-1", headers["x-trace"]
    assert_equal "Bearer #{TEST_API_KEY}", headers["authorization"]
    assert_equal(1, headers.keys.count { |name| name.casecmp?("authorization") })
  end
end

class CheckBulkTest < Minitest::Test
  include TestSupport

  def test_sends_one_request_with_a_bare_json_array_of_normalized_eins
    adapter = FakeAdapter.new([{ body: envelope([nonprofit_fixture, nonprofit_fixture("ein" => "996589560")]) }])
    result = client_with(adapter).nonprofits.check_bulk(%w[41-1787097 996589560])

    assert_equal 1, adapter.requests.size

    request = adapter.requests.first

    assert_equal :post, request.http_method
    assert_equal "#{BASE_URL}/api/entities/nonprofitcheckbulk/v1/us/eins", request.url
    assert_equal "application/json", request.headers["content-type"]
    assert_equal %w[411787097 996589560], JSON.parse(request.body)

    assert_equal 2, result.organizations.size
    assert_equal "996589560", result.organizations[1].ein
  end

  def test_preserves_input_order_and_duplicates_by_default
    adapter = FakeAdapter.new([{ body: envelope([]) }])
    client_with(adapter).nonprofits.check_bulk(%w[996589560 41-1787097 996589560])

    assert_equal %w[996589560 411787097 996589560], JSON.parse(adapter.requests.first.body)
  end

  def test_removes_duplicates_only_when_dedupe_is_requested
    adapter = FakeAdapter.new([{ body: envelope([]) }])
    client_with(adapter).nonprofits.check_bulk(%w[996589560 996589560 41-1787097], dedupe: true)

    assert_equal %w[996589560 411787097], JSON.parse(adapter.requests.first.body)
  end

  def test_rejects_an_empty_collection_locally
    adapter = FakeAdapter.new([{ body: envelope([]) }])

    assert_raises(NCP::ValidationError) { client_with(adapter).nonprofits.check_bulk([]) }
    assert_empty adapter.requests
  end

  def test_rejects_the_whole_batch_when_one_ein_is_malformed_before_sending
    adapter = FakeAdapter.new([{ body: envelope([]) }])

    assert_raises(NCP::ValidationError) { client_with(adapter).nonprofits.check_bulk(%w[411787097 not-an-ein]) }
    assert_empty adapter.requests
  end

  def test_enforces_the_server_batch_limit_locally_from_a_single_constant
    adapter = FakeAdapter.new([{ body: envelope([]) }])
    too_many = Array.new(NCP::MAX_BULK_EINS + 1, "411787097")

    error = assert_raises(NCP::ValidationError) { client_with(adapter).nonprofits.check_bulk(too_many) }

    assert_includes error.message, "at most #{NCP::MAX_BULK_EINS} EINs"
    assert_empty adapter.requests
  end

  def test_accepts_exactly_the_batch_limit
    adapter = FakeAdapter.new([{ body: envelope([]) }])
    client_with(adapter).nonprofits.check_bulk(Array.new(NCP::MAX_BULK_EINS, "411787097"))

    assert_equal 1, adapter.requests.size
  end

  def test_applies_the_limit_after_dedupe
    adapter = FakeAdapter.new([{ body: envelope([]) }])
    duplicate_heavy = Array.new(NCP::MAX_BULK_EINS + 10) { |index| (100_000_000 + (index % 10)).to_s }

    client_with(adapter).nonprofits.check_bulk(duplicate_heavy, dedupe: true)

    assert_equal 10, JSON.parse(adapter.requests.first.body).size
  end

  def test_surfaces_per_item_not_found_results_from_a_successful_response
    body = envelope(
      [nonprofit_fixture],
      "nonprofit_check_count" => 1,
      "errors" => [
        {
          "resource" => "nonprofitcheckbulk",
          "reason" => "There are no matching nonprofits in our records for this set of EINs",
          "code" => 404,
          "eins" => ["996589560"]
        }
      ]
    )
    adapter = FakeAdapter.new([{ status: 200, body: body }])
    result = client_with(adapter).nonprofits.check_bulk(%w[411787097 996589560])

    assert_equal 1, result.organizations.size
    assert_equal ["996589560"], result.not_found_eins
    assert_equal 404, result.errors.first.code
    assert_equal 1, result.check_count
  end

  def test_reads_not_found_eins_given_as_a_comma_separated_string
    body = envelope([nonprofit_fixture], "errors" => [{ "code" => 404, "eins" => "996589560, 123456789," }])
    adapter = FakeAdapter.new([{ body: body }])

    assert_equal %w[996589560 123456789], client_with(adapter).nonprofits.check_bulk(["411787097"]).not_found_eins
  end

  def test_reads_organizations_from_a_wrapped_data_object_as_well_as_a_bare_array
    adapter = FakeAdapter.new([{ body: envelope({ "organizations" => [nonprofit_fixture] }) }])

    assert_equal 1, client_with(adapter).nonprofits.check_bulk(["411787097"]).organizations.size
  end

  def test_rejects_a_non_array_input_locally
    adapter = FakeAdapter.new([{ body: envelope([]) }])

    ["411787097", nil, Set["411787097"]].each do |input|
      assert_raises(NCP::ValidationError) { client_with(adapter).nonprofits.check_bulk(input) }
    end

    assert_empty adapter.requests
  end
end
