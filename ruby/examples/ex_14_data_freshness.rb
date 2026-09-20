# frozen_string_literal: true

# EX-14 — Data freshness and report metadata.
#
# Every source on the response carries its own date. A check is a statement about
# the data as of those dates — not as of the moment you called.
#
# This example surfaces each timestamp, computes an age, and applies a re-review
# rule the application owns. The SDK supplies the dates and nothing else: there
# is no `stale?` method and no default threshold, because 90 days is prudent for
# one workflow and reckless for another.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_14_data_freshness.rb

require "time"
require_relative "lib/api_date"
require_relative "lib/fixture_api"
require_relative "lib/print"

include Print

# The application's own rule. Change it here, in one place.
RE_REVIEW_AFTER_DAYS = 90

TIMESTAMP_FIELDS = %w[organization_info_last_modified report_date most_recent_bmf most_recent_pub78].freeze

def age_in_days(value, now)
  parsed = ApiDate.parse(value)
  parsed && ApiDate.age_in_days(parsed, now)
end

FixtureApi.with_fixture_api do |client|
  [
    ["recently refreshed", FixtureApi::EINS[:public_charity]],
    ["every source is old", FixtureApi::EINS[:stale_data]],
    ["some dates were not returned", FixtureApi::EINS[:sparse_identity]]
  ].each do |label, ein|
    result = client.nonprofits.check(ein)
    nonprofit = result.nonprofit

    if nonprofit.nil?
      puts "No record for #{ein}."
      next
    end

    now = Time.now
    timestamps = TIMESTAMP_FIELDS.to_h { |name| [name, nonprofit[name]] }

    heading "#{label} — #{nonprofit.organization_name}"

    timestamps.each do |name, value|
      age = age_in_days(value, now)

      puts "  #{name.ljust(34)} #{(value || "<null>").ljust(26)} #{age.nil? ? "age unknown" : "#{age} days old"}"
    end

    # `report_date` is when this response was generated. The source dates are
    # when each underlying list was last refreshed. They answer different
    # questions, and the older one governs.
    ages = timestamps.filter_map do |name, value|
      age = age_in_days(value, now)
      { name: name, age: age } unless age.nil?
    end

    oldest = ages.max_by { |entry| entry[:age] }
    undated = timestamps.select { |_name, value| value.nil? || value.empty? }.keys

    bullet "oldest source: #{oldest[:name]} at #{oldest[:age]} days" if oldest
    undated.each { |name| bullet "no date returned for #{name} — age cannot be established" }

    needs_re_review = (oldest.nil? || oldest[:age] > RE_REVIEW_AFTER_DAYS) || !undated.empty?

    field "request timing (timeTaken ms)", result.time_taken_ms
    field "checked at (UTC)", now.utc.iso8601
    field "re-review rule (> #{RE_REVIEW_AFTER_DAYS} days)",
          if needs_re_review
            "schedule a re-review — a source is past the threshold or undated"
          else
            "within the freshness window — no re-review scheduled"
          end

    # Store the timestamps alongside your verification record, not just the
    # outcome. Six months from now "we checked and it was fine" is not an answer;
    # "we checked on this date against BMF data published on that date" is.
    next unless ein == FixtureApi::EINS[:public_charity]

    puts "\n  stored with the verification record:"
    json_block({ "ein" => nonprofit.ein, "checked_at" => now.utc.iso8601, "request_id" => result.request_id }
                 .merge(timestamps))
  end
end

note "A fresh response is not a fresh fact. IRS lists publish on their own schedule,\n" \
     "so a check performed today can reflect a revocation posted weeks ago and not\n" \
     "yet published — see ex_29 for the pre-payment recheck this implies."
