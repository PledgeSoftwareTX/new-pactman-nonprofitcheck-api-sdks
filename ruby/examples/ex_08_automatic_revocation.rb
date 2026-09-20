# frozen_string_literal: true

# EX-08 — Automatic revocation detected.
#
# An organization that fails to file for three consecutive years has its
# exemption revoked automatically and appears in the IRS Automatic Revocation of
# Exemption (AROE) data. The API reports that with `revocation_code` and
# `revocation_date`.
#
# This example flags the record and preserves the source fields verbatim. It does
# not decide the outcome — blocking, holding, or reviewing is your policy.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_08_automatic_revocation.rb

require "time"
require_relative "lib/fixture_api"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

# The application's policy, in one place, expressed against source fields.
POLICY = {
  on_revoked_without_reinstatement: "block",
  on_revoked_with_reinstatement: "manual_review",
  on_no_revocation_data: "continue"
}.freeze

Assessment = Data.define(:action, :reason, :aroe)

def filled?(value)
  !value.nil? && value != ""
end

def assess_revocation(nonprofit)
  aroe = NCP::Sources.aroe(nonprofit)

  return Assessment.new(POLICY[:on_no_revocation_data], "No revocation fields were returned.", aroe) if aroe.nil?

  unless filled?(aroe.revocation_code) || filled?(aroe.revocation_date)
    return Assessment.new(POLICY[:on_no_revocation_data], "Revocation fields were returned and are empty.", aroe)
  end

  if filled?(aroe.reinstatement_date)
    Assessment.new(POLICY[:on_revoked_with_reinstatement], "Revoked, with a reinstatement date present — see ex_09.",
                   aroe)
  else
    Assessment.new(POLICY[:on_revoked_without_reinstatement],
                   "Appears in the Automatic Revocation data with no reinstatement.", aroe)
  end
end

FixtureApi.with_fixture_api do |client|
  [FixtureApi::EINS[:revoked], FixtureApi::EINS[:public_charity]].each do |ein|
    result = client.nonprofits.check(ein)
    nonprofit = result.nonprofit

    if nonprofit.nil?
      puts "No record for #{ein}."
      next
    end

    assessment = assess_revocation(nonprofit)
    bmf = NCP::Sources.bmf(nonprofit)

    heading "#{nonprofit.organization_name} (#{nonprofit.ein})"
    field "revocation_code", returned(assessment.aroe, :revocation_code)
    field "revocation_date", returned(assessment.aroe, :revocation_date)
    field "reinstatement_date", returned(assessment.aroe, :reinstatement_date)

    # Revocation shows up in the other sources too. Capture what each one said,
    # rather than letting one field speak for all of them.
    field "bmf_status", returned(bmf, :status)
    field "pub78_verified", returned(NCP::Sources.pub78(nonprofit), :verified)
    field "exempt_status_code", returned(bmf, :exempt_status_code)

    field "policy action", assessment.action
    field "reason", assessment.reason

    # What you keep is what you can explain later. Store the source fields, the
    # request identifier, and the time you looked — not just the verdict.
    audit_record = {
      ein: nonprofit.ein,
      checked_at: Time.now.utc.iso8601,
      request_id: result.request_id,
      action: assessment.action,
      source_findings: nonprofit.to_h.slice(
        "revocation_code", "revocation_date", "reinstatement_date", "bmf_status", "pub78_verified"
      )
    }

    puts "\n  audit record:"
    json_block audit_record
  end
end

note "The SDK reports what the AROE data says. It does not decide whether a revoked\n" \
     "organization may receive a donation, a grant, or a payout — that is a legal and\n" \
     "compliance determination your application owns."
