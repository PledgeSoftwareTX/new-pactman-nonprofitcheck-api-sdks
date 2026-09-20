# frozen_string_literal: true

require_relative "test_helper"

class SourcesTest < Minitest::Test
  include TestSupport

  def nonprofit(overrides = {})
    NCP::Nonprofit.new(nonprofit_fixture(overrides))
  end

  def test_maps_publication_78_fields
    pub78 = NCP::Sources.pub78(nonprofit)

    assert_instance_of NCP::Pub78Source, pub78
    assert pub78.verified
    assert_equal "411787097", pub78.ein
    assert_equal "Example Nonprofit", pub78.organization_name
    assert_equal "12/12/2025 12:00:00 AM", pub78.most_recent
    assert_equal "50%", pub78.organization_types.first.deductibility_limitation
  end

  def test_maps_business_master_file_fields
    bmf = NCP::Sources.bmf(nonprofit)

    assert bmf.status
    assert_equal "03", bmf.subsection
    assert_equal "501(c)(3) Public Charity", bmf.subsection_description
    assert_equal "Public charity described in section 509(a)(1) or (2)", bmf.foundation_code_description
    assert_equal "12/09/2025 12:00:00 AM", bmf.most_recent
  end

  def test_maps_automatic_revocation_fields
    aroe = NCP::Sources.aroe(nonprofit("revocation_code" => "01", "revocation_date" => "3/06/2026 9:41:03 PM",
                                       "reinstatement_date" => "3/07/2026 9:41:03 PM"))

    assert_equal "01", aroe.revocation_code
    assert_equal "3/07/2026 9:41:03 PM", aroe.reinstatement_date
  end

  def test_maps_ofac_verbatim_without_deriving_a_boolean
    ofac = NCP::Sources.ofac(nonprofit)

    assert_includes ofac.status, "NOT included"
    assert_equal ["status"], ofac.keys
    refute_respond_to ofac, :match?
    refute_respond_to ofac, :matched
  end

  def test_copies_values_rather_than_duplicating_them
    record = nonprofit

    assert_same record["pub78_organization_name"], NCP::Sources.pub78(record)["organization_name"]
    assert_same record["organization_types"], NCP::Sources.pub78(record)["organization_types"]
  end

  def test_keeps_a_missing_source_distinct_from_an_explicit_negative
    without_sources = NCP::Nonprofit.new({ "ein" => "411787097", "organization_name" => "NO SOURCES" })
    negative = nonprofit("pub78_verified" => false)
    all_null = nonprofit(
      "pub78_verified" => nil, "pub78_organization_name" => nil, "pub78_ein" => nil, "pub78_city" => nil,
      "pub78_state" => nil, "pub78_indicator" => nil, "pub78_church_message" => nil, "organization_types" => nil,
      "most_recent_pub78" => nil
    )

    assert_nil NCP::Sources.ofac(without_sources)
    assert_nil NCP::Sources.pub78(without_sources)

    assert_equal false, NCP::Sources.pub78(negative).verified

    refute_nil NCP::Sources.pub78(all_null)
    assert_nil NCP::Sources.pub78(all_null).verified
    assert NCP::Sources.pub78(all_null).key?(:verified)
  end

  def test_reports_a_source_as_present_when_only_some_of_its_fields_were_returned
    bmf = NCP::Sources.bmf(NCP::Nonprofit.new({ "ein" => "411787097", "bmf_status" => false }))

    assert_equal false, bmf.status
    assert_nil bmf.subsection
    refute bmf.key?(:subsection)
  end

  def test_accepts_a_plain_hash_with_string_or_symbol_keys
    assert NCP::Sources.bmf({ "bmf_status" => true }).status
    assert NCP::Sources.bmf({ bmf_status: true }).status
    assert_raises(ArgumentError) { NCP::Sources.bmf(nil) }
  end

  def test_never_produces_a_composite_verdict
    record = nonprofit
    projections = [NCP::Sources.pub78(record), NCP::Sources.bmf(record), NCP::Sources.aroe(record),
                   NCP::Sources.ofac(record)]
    names = projections.flat_map(&:keys) + projections.flat_map { |view| view.class.public_instance_methods(false) }

    names.each { |name| refute_match(/approved|eligible|safe|passed|verdict/i, name.to_s) }
  end
end
