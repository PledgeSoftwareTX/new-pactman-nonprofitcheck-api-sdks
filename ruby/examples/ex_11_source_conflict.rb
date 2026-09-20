# frozen_string_literal: true

# EX-11 — Cross-source conflict or inconsistency.
#
# `irs_bmf_pub78_conflict` is true when the Business Master File and Publication
# 78 disagree about an organization. The API reports the disagreement instead of
# resolving it, and so does this example: it records what each source said and
# creates a review outcome.
#
# Silently preferring one source is the failure mode here. Whichever you pick,
# you will be wrong for some organization, and you will have destroyed the
# evidence that would have shown it.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_11_source_conflict.rb

require "time"
require_relative "lib/fixture_api"
require_relative "lib/matching"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

# Case and whitespace differences are not disagreements. See ex_04.
LOOSELY = ->(value) { value.to_s.upcase.strip }

# Fields the two IRS sources both report, so disagreement is visible per pair.
CROSS_SOURCE_PAIRS = [
  { label: "organization name", field: :organization_name, normalize: Matching.method(:normalize_name) },
  { label: "EIN", field: :ein, normalize: LOOSELY },
  { label: "city", field: :city, normalize: LOOSELY },
  { label: "state", field: :state, normalize: LOOSELY }
].freeze

def collect_conflicts(nonprofit)
  bmf = NCP::Sources.bmf(nonprofit)
  pub78 = NCP::Sources.pub78(nonprofit)
  findings = []

  # The flag the API sets. This is the authoritative signal; the per-field
  # comparison below only explains it.
  if nonprofit.irs_bmf_pub78_conflict == true
    findings << { field: "irs_bmf_pub78_conflict", detail: "The API flagged a BMF / Publication 78 disagreement." }
  end

  if bmf&.status == true && pub78&.verified == false
    findings << { field: "bmf_status vs pub78_verified",
                  detail: "The BMF lists the organization as exempt; Publication 78 does not list it." }
  end

  if bmf&.status == false && pub78&.verified == true
    findings << { field: "bmf_status vs pub78_verified",
                  detail: "Publication 78 lists the organization; the BMF does not show it as exempt." }
  end

  CROSS_SOURCE_PAIRS.each do |pair|
    bmf_value = bmf&.[](pair[:field])
    pub78_value = pub78&.[](pair[:field])

    # Only compare when both sources actually supplied a value. A field one
    # source omitted is missing data, not a conflict.
    next if bmf_value.nil? || pub78_value.nil?
    next if pair[:normalize].call(bmf_value) == pair[:normalize].call(pub78_value)

    findings << { field: pair[:label], detail: "BMF \"#{bmf_value}\" vs Publication 78 \"#{pub78_value}\"" }
  end

  findings
end

FixtureApi.with_fixture_api do |client|
  [FixtureApi::EINS[:conflicted], FixtureApi::EINS[:public_charity]].each do |ein|
    result = client.nonprofits.check(ein)
    nonprofit = result.nonprofit

    if nonprofit.nil?
      puts "No record for #{ein}."
      next
    end

    conflicts = collect_conflicts(nonprofit)

    heading "#{nonprofit.organization_name} (#{nonprofit.ein})"
    field "irs_bmf_pub78_conflict", returned(nonprofit, :irs_bmf_pub78_conflict)
    field "conflicting signals", conflicts.size

    conflicts.each { |conflict| bullet "#{conflict[:field]}: #{conflict[:detail]}" }
    bullet "sources agree on every field both of them returned" if conflicts.empty?

    # Nothing is chosen. Both sides are kept, side by side, for the reviewer.
    bmf = NCP::Sources.bmf(nonprofit)
    pub78 = NCP::Sources.pub78(nonprofit)

    puts "\n  source-by-source view:"
    puts "    #{"field".ljust(20)} #{"BMF".ljust(30)} Publication 78"

    CROSS_SOURCE_PAIRS.each do |pair|
      puts "    #{pair[:label].ljust(20)} #{render(returned(bmf, pair[:field])).ljust(30)} " \
           "#{render(returned(pub78, pair[:field]))}"
    end

    puts "    #{"exempt/listed".ljust(20)} #{render(returned(bmf, :status)).ljust(30)} " \
         "#{render(returned(pub78, :verified))}"

    outcome = conflicts.empty? ? "continue" : "manual_review"

    puts
    field "policy outcome", outcome

    next if conflicts.empty?

    review_record = {
      ein: nonprofit.ein,
      request_id: result.request_id,
      checked_at: Time.now.utc.iso8601,
      report_date: nonprofit.report_date,
      conflicts: conflicts,
      sources: { bmf: bmf, pub78: pub78, aroe: NCP::Sources.aroe(nonprofit), ofac: NCP::Sources.ofac(nonprofit) }
    }

    puts "    review record: #{JSON.generate(review_record).bytesize} bytes retained"
    puts "    conflicting fields: #{conflicts.map { |item| item[:field] }.join(", ")}"
  end
end

note "A conflict is a fact about the data, not a fact about the organization. Record\n" \
     "both sources, escalate, and let a person decide which one governs your workflow."
