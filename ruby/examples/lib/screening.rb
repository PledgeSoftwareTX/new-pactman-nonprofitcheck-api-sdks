# frozen_string_literal: true

# Shared screening helpers for the workflow examples (ex_26 to ex_30).
#
# These gather what the API said into one Hash. They do not decide anything:
# there is no `approved`, no `eligible`, no `safe`. Each workflow applies its own
# policy to this evidence, and the policies differ on purpose — a donation
# platform, a DAF and a payout gate reach different conclusions from identical
# data, and all three are right for their own obligations.

require_relative "api_date"
require_relative "print"

module Screening
  Sources = Pactman::NonprofitCheckPlus::Sources

  # Fields worth diffing between two checks of the same organization.
  MATERIAL_FIELDS = %w[
    organization_name bmf_status exempt_status_code pub78_verified revocation_code revocation_date
    reinstatement_date ofac_state irs_bmf_pub78_conflict foundation_type_code subsection_description
  ].freeze

  module_function

  # The four OFAC states from ex_10. `unavailable` is never a pass.
  def ofac_state(nonprofit)
    ofac = Sources.ofac(nonprofit)

    return "unavailable" if ofac.nil?
    return "null" if ofac.status.nil?
    return "match" if ofac.status.match?(/UID:/i)

    ofac.status.match?(/NOT included/i) ? "no_match" : "unrecognized"
  end

  # Age in days of the oldest source date on the record, or `nil` if undatable.
  def oldest_source_age_days(nonprofit, now = Time.now)
    dates = [nonprofit.most_recent_bmf, nonprofit.most_recent_pub78, nonprofit.organization_info_last_modified]
            .filter_map { |value| ApiDate.parse(value) }

    dates.empty? ? nil : ApiDate.age_in_days(dates.min, now)
  end

  # A flat, comparable view of the findings — every value copied from the response.
  #
  # `nil` means the API returned null; {Print::NOT_RETURNED} means it returned no
  # such field. Both are preserved so a consumer can tell them apart, and both
  # serialize: the marker as the string `"<not returned>"`.
  def collect_findings(nonprofit, now = Time.now)
    bmf = Sources.bmf(nonprofit)
    pub78 = Sources.pub78(nonprofit)
    aroe = Sources.aroe(nonprofit)

    {
      "ein" => nonprofit.ein,
      "organization_name" => nonprofit.organization_name,
      "organization_name_aka" => nonprofit.organization_name_aka,

      "bmf_returned" => !bmf.nil?,
      "bmf_status" => Print.returned(bmf, :status),
      "exempt_status_code" => Print.returned(bmf, :exempt_status_code),
      "subsection_description" => Print.returned(bmf, :subsection_description),
      "foundation_type_code" => Print.returned(bmf, :foundation_type_code),
      "foundation_type_description" => Print.returned(bmf, :foundation_type_description),

      "pub78_returned" => !pub78.nil?,
      "pub78_verified" => Print.returned(pub78, :verified),
      "deductibility_limitations" => (pub78&.organization_types || []).filter_map do |entry|
        entry&.deductibility_limitation
      end,

      "revocation_code" => Print.returned(aroe, :revocation_code),
      "revocation_date" => Print.returned(aroe, :revocation_date),
      "reinstatement_date" => Print.returned(aroe, :reinstatement_date),
      "revoked" => present?(aroe&.revocation_code) || present?(aroe&.revocation_date),
      "reinstated" => present?(aroe&.reinstatement_date),

      "ofac_state" => ofac_state(nonprofit),
      "ofac_status" => Print.returned(nonprofit, :ofac_status),

      "irs_bmf_pub78_conflict" => Print.returned(nonprofit, :irs_bmf_pub78_conflict),

      "report_date" => nonprofit.report_date,
      "organization_info_last_modified" => nonprofit.organization_info_last_modified,
      "oldest_source_age_days" => oldest_source_age_days(nonprofit, now)
    }
  end

  # Human-readable reasons a workflow might want to stop. No verdict attached.
  def concerns(findings, stale_after_days: 120)
    found = []

    if findings["revoked"] && !findings["reinstated"]
      found << "listed in the IRS Automatic Revocation data with no reinstatement"
    end
    if findings["revoked"] && findings["reinstated"]
      found << "revoked and later reinstated — the lapse period may still matter"
    end
    found << "a possible OFAC SDN match was reported" if findings["ofac_state"] == "match"

    unless %w[no_match match].include?(findings["ofac_state"])
      found << "OFAC screening result is #{findings["ofac_state"]} — nothing was cleared"
    end

    found << "the BMF and Publication 78 disagree about this organization" if findings["irs_bmf_pub78_conflict"] == true
    found << "the BMF does not show the organization as exempt" if findings["bmf_status"] == false
    found << "the organization is not listed in Publication 78" if findings["pub78_verified"] == false
    found << "no BMF data was returned" unless findings["bmf_returned"]
    found << "no Publication 78 data was returned" unless findings["pub78_returned"]

    age = findings["oldest_source_age_days"]

    if age.nil?
      found << "no source date was returned, so data age cannot be established"
    elsif age > stale_after_days
      found << "the oldest source is #{age} days old"
    end

    found
  end

  Change = Data.define(:field, :before, :after)

  # Changes between a stored set of findings and a fresh one.
  def diff_findings(previous, current, fields = MATERIAL_FIELDS)
    fields.filter_map do |key|
      before = previous.nil? ? Print::NOT_RETURNED : previous.fetch(key, Print::NOT_RETURNED)
      after = current.fetch(key, Print::NOT_RETURNED)

      Change.new(field: key, before: before, after: after) unless comparable(before) == comparable(after)
    end
  end

  def present?(value)
    !value.nil? && !value.equal?(Print::NOT_RETURNED) && value != ""
  end

  def comparable(value)
    value.equal?(Print::NOT_RETURNED) ? :not_returned : value
  end
end
