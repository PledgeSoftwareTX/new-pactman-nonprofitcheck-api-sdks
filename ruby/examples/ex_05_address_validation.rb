# frozen_string_literal: true

# EX-05 — Validating the address the API returned.
#
# The response carries `address_line1`, `address_line2`, `city`, `state`,
# `state_name` and `zip`. This example asks one question about them: is this
# address well-formed and self-consistent enough to act on?
#
# Three outcomes, and the middle one is the point:
#
#   usable        every required component came back, and nothing contradicts
#   incomplete    a required component was not returned — absence, not error
#   inconsistent  the components came back and disagree with each other
#
# A record can be complete and wrong. `state` and `state_name` are two fields for
# one fact, and a ZIP already encodes the state a third time, so an extract that
# has been transcribed, merged or truncated can contradict itself while every
# field passes a nil check.
#
# Well-formed is not deliverable. Nothing here asks USPS whether mail arrives;
# see the closing note for where that call would go.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_05_address_validation.rb

require_relative "lib/address"
require_relative "lib/fixture_api"
require_relative "lib/print"

include Print

# One clean record, one with components missing, one that contradicts itself.
SUBJECTS = [
  { label: "Complete record", ein: FixtureApi::EINS[:public_charity] },
  { label: "Sparse record — components not returned", ein: FixtureApi::EINS[:sparse_identity] },
  { label: "Complete record that disagrees with itself", ein: FixtureApi::EINS[:inconsistent_address] }
].freeze

# Your policy, not the SDK's. This one refuses to treat absence as validity.
def route(verdict)
  case verdict
  when "usable" then "continue — the address is complete and self-consistent"
  when "incomplete" then "manual review — too little address data came back to act on"
  else "manual review — the returned components contradict each other"
  end
end

MARKS = { "pass" => "✓", "fail" => "✗", "not_checkable" => "·" }.freeze

FixtureApi.with_fixture_api do |client|
  SUBJECTS.each do |subject|
    nonprofit = client.nonprofits.check(subject[:ein]).nonprofit

    if nonprofit.nil?
      puts "No record for #{subject[:ein]}."
      next
    end

    heading "#{subject[:label]} — #{nonprofit.organization_name} (#{nonprofit.ein})"

    # What came back, before any judgement. `<null>` and `<not returned>` print
    # differently here for the same reason they do everywhere else.
    Address::ADDRESS_COMPONENTS.each { |component| field component, returned(nonprofit, component), 16 }

    result = Address.validate(nonprofit)

    puts "\n  checks:"

    result.checks.each do |entry|
      # A check that could not run is marked apart from one that passed. An
      # unrunnable check has confirmed nothing about this address.
      bullet "#{MARKS.fetch(entry.outcome)} #{entry.label.ljust(38)} #{entry.outcome.ljust(14)}#{entry.detail}".rstrip
    end

    puts
    field "components not returned", result.missing.empty? ? "<none>" : result.missing.join(", ")
    field "checks failed", result.failures.empty? ? "<none>" : result.failures.map(&:id).join(", ")
    field "verdict", result.verdict
    field "routed to", route(result.verdict)

    # Only now is it reasonable to store this as the organization's address, and
    # even now it is the IRS filing address, not proof of an occupant.
    field "safe to persist as-is", "yes — no component is missing or contradicted" if Address.usable?(result.verdict)
  end
end

note "Complete is not the same as correct, and correct is not the same as deliverable.\n" \
     "These checks are structural: they run offline, need no second credential, and\n" \
     "catch the damage that survives a nil check. A deliverability verdict — USPS,\n" \
     "Lob, Smarty, Google Address Validation — is a network call with its own key,\n" \
     "and it belongs as one more check inside Address.validate, not as a\n" \
     "replacement for these. Bear in mind what a failure there would mean: an IRS\n" \
     "filing address is often a PO box, an accountant or a registered agent, so a\n" \
     "deliverability miss is a fact about the mailbox, never about the charity."
