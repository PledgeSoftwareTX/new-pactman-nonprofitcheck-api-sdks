# frozen_string_literal: true

# EX-10 — OFAC screening result.
#
# The API reports OFAC as a sentence, not a flag. Four results have to stay
# distinguishable, because they route to four different places:
#
#   no_match     the organization was screened and was not on the SDN list
#   match        a close match was found — never auto-clear this
#   null         the field was returned with no value
#   unavailable  no OFAC field was returned at all; nothing was screened
#
# The SDK exposes no `ofac_match?` boolean. Deriving one means pattern-matching
# English that the source can reword at any time, and a screening step that
# silently starts returning "no match" because a sentence changed is worse than no
# screening step.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_10_ofac_screening.rb

require_relative "lib/fixture_api"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

Finding = Data.define(:state, :status)

# Classifies the OFAC finding into the four states above.
#
# The one textual test here is for the SDN unique identifier the API includes on
# a match. It is treated as a signal to escalate, never as a signal to clear:
# anything unrecognized falls through to `needs_review`.
def classify_ofac(nonprofit)
  ofac = NCP::Sources.ofac(nonprofit)

  return Finding.new("unavailable", NOT_RETURNED) if ofac.nil?
  return Finding.new("null", nil) if ofac.status.nil?
  return Finding.new("match", ofac.status) if ofac.status.match?(/UID:/i)
  return Finding.new("no_match", ofac.status) if ofac.status.match?(/NOT included/i)

  Finding.new("needs_review", ofac.status)
end

# Four states, four destinations. None of them is "approve automatically".
ROUTING = {
  "no_match" => "continue — screened against the SDN list with no match",
  "match" => "block and escalate to compliance — a possible SDN match must be adjudicated",
  "null" => "hold — the field was returned empty; treat as unscreened, not as cleared",
  "unavailable" => "hold — no OFAC data was returned; nothing was screened",
  "needs_review" => "hold — the status text was not recognized by this application"
}.freeze

FixtureApi.with_fixture_api do |client|
  [
    ["no match", FixtureApi::EINS[:public_charity]],
    ["possible match", FixtureApi::EINS[:ofac_match]],
    ["null status", FixtureApi::EINS[:ofac_unavailable]],
    ["source not returned", FixtureApi::EINS[:sparse_identity]]
  ].each do |label, ein|
    nonprofit = client.nonprofits.check(ein).nonprofit

    if nonprofit.nil?
      puts "No record for #{ein}."
      next
    end

    finding = classify_ofac(nonprofit)

    heading "#{label} — #{nonprofit.organization_name}"
    field "ofac_status", finding.status
    field "Sources.ofac returned", NCP::Sources.ofac(nonprofit).nil? ? "nil (no OFAC fields)" : "an OfacSource"
    field "state", finding.state
    field "routed to", ROUTING.fetch(finding.state)
  end
end

note "Today the API substitutes the \"NOT included\" sentence when it has no OFAC value,\n" \
     "so the null and unavailable branches are defensive. They still belong in your\n" \
     "code: an absent screening result must never arrive at your approve path.\n\n" \
     "A no-match result is a screening outcome from one list on one date. It is not\n" \
     "sanctions clearance, and it does not cover any other watchlist you are obliged\n" \
     "to check."
