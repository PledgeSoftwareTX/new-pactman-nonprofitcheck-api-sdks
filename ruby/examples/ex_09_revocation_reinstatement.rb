# frozen_string_literal: true

# EX-09 — Revoked organization with reinstatement data.
#
# A record can carry both a revocation date and a reinstatement date. The two
# stay separately accessible, because the gap between them matters: a donation
# made while the exemption was revoked is not retroactively fixed by a later
# reinstatement, and reinstatement can be retroactive or not.
#
# This example surfaces both dates and the interval, and still routes the record
# to review. Reinstatement resolves one question, not every question.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_09_revocation_reinstatement.rb

require "time"
require_relative "lib/api_date"
require_relative "lib/fixture_api"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

FixtureApi.with_fixture_api do |client|
  result = client.nonprofits.check(FixtureApi::EINS[:reinstated])
  nonprofit = result.nonprofit

  if nonprofit.nil?
    puts "No record returned."
    next
  end

  aroe = NCP::Sources.aroe(nonprofit)

  heading "#{nonprofit.organization_name} (#{nonprofit.ein})"

  # Both dates are their own field. Nothing collapses them into a single
  # "currently revoked" boolean, because that boolean would lose the interval.
  field "revocation_code", returned(aroe, :revocation_code)
  field "revocation_date", returned(aroe, :revocation_date)
  field "reinstatement_date", returned(aroe, :reinstatement_date)

  # The API formats dates as `M/DD/YYYY h:mm:ss AM`. Parse, never reformat in place.
  revoked_at = ApiDate.parse(aroe&.revocation_date)
  reinstated_at = ApiDate.parse(aroe&.reinstatement_date)

  heading "Derived, in application code"

  if revoked_at && reinstated_at
    bullet "revoked on #{revoked_at.strftime("%F")}"
    bullet "reinstated on #{reinstated_at.strftime("%F")}"
    bullet "exemption lapsed for #{ApiDate.age_in_days(revoked_at, reinstated_at)} days"
    bullet "donations dated inside that window may need separate handling"
  elsif revoked_at
    bullet "revoked, with no reinstatement date returned"
  else
    bullet "no revocation history returned"
  end

  heading "What the other sources say now"
  field "bmf_status", returned(NCP::Sources.bmf(nonprofit), :status)
  field "pub78_verified", returned(NCP::Sources.pub78(nonprofit), :verified)
  field "irs_bmf_pub78_conflict", returned(nonprofit, :irs_bmf_pub78_conflict)

  heading "Outcome"

  [
    "Was the reinstatement retroactive to the revocation date?",
    "Do gifts made during the lapse need to be re-characterized?",
    "Does your grant agreement require continuous exemption?",
    "Has the organization filed since reinstatement?"
  ].each { |question| bullet question }

  puts
  field "policy action", "manual review — reinstatement is recorded, and the record still has history"

  puts "\n  evidence retained:"
  json_block(
    { ein: nonprofit.ein, request_id: result.request_id, checked_at: Time.now.utc.iso8601 }
      .merge(nonprofit.to_h.slice("revocation_date", "reinstatement_date", "revocation_code"))
  )
end

note "The API answers \"what does the IRS revocation data show\". It does not answer\n" \
     "\"is this organization eligible today\" — that needs your policy, and often your\n" \
     "counsel."
