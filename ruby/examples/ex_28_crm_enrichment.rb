# frozen_string_literal: true

# EX-28 — Nonprofit CRM enrichment or synchronization.
#
# Uses a verified EIN as the stable key to refresh a CRM record with canonical
# name, AKA, address, status, classification, profile URL and last-modified
# metadata.
#
# The rule that makes this safe to run on a schedule: a `null` from the API is an
# absence of data, not an instruction to erase. A sync that overwrites a good,
# human-entered address with `nil` because one IRS field was empty is a data-loss
# bug that looks like a feature until someone notices.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_28_crm_enrichment.rb

require "time"
require_relative "lib/fixture_api"
require_relative "lib/print"

include Print

EINS = FixtureApi::EINS

# Fields this CRM keeps in sync, named as they are on the response.
SYNCED_FIELDS = %w[
  organization_name organization_name_aka address_line1 address_line2 city state state_name zip
  subsection_description foundation_type_description bmf_status pub78_verified pactman_org_url
  organization_info_last_modified
].freeze

EMPTY_ROW = SYNCED_FIELDS.to_h { |key| [key, nil] }.freeze

# Existing CRM rows, keyed by EIN. Some hold better data than the API returns.
crm = {
  EINS[:public_charity] => EMPTY_ROW.merge(
    "ein" => EINS[:public_charity], "organization_name" => "Meals Today", "address_line1" => "50 Lowell Ave",
    "address_line2" => "Suite 3B", "city" => "Westfield", "state" => "MA", "state_name" => "Massachusetts",
    "zip" => "01085-2643", "verified_at" => nil
  ),
  EINS[:sparse_identity] => EMPTY_ROW.merge(
    "ein" => EINS[:sparse_identity], "organization_name" => "Quiet Harbor Trust", "organization_name_aka" => "QHT",
    "address_line1" => "PO Box 118",
    # Entered by a fundraiser who spoke to the organization. The API returns null
    # for these; that must not wipe them.
    "city" => "Rockport", "state" => "ME", "state_name" => "Maine", "zip" => "04856",
    "verified_at" => "2026-01-04T09:12:00Z"
  )
}

Merge = Data.define(:row, :updates, :skipped)

# Merges a response into a CRM row.
#
# A field is written only when the API returned a usable value. `null` and absent
# both mean "no update available" — never "clear this".
def merge(record, nonprofit)
  updates = []
  skipped = []
  row = record.dup

  SYNCED_FIELDS.each do |key|
    incoming = nonprofit[key]

    if incoming.nil?
      skipped << [key, nonprofit.key?(key) ? "API returned null" : "API returned no field"]
      next
    end

    next if record[key] == incoming

    updates << [key, record[key], incoming]
    row[key] = incoming
  end

  Merge.new(row: row, updates: updates, skipped: skipped)
end

FixtureApi.with_fixture_api do |client|
  eins = crm.keys
  result = client.nonprofits.check_bulk(eins)

  # EIN is the join key: stable, returned on every record, and the same value
  # your CRM already stores. Names change; EINs do not.
  by_ein = result.organizations.to_h { |org| [org.ein, org] }

  eins.each do |ein|
    record = crm.fetch(ein)
    nonprofit = by_ein[ein]

    heading "CRM record #{ein}"

    if nonprofit.nil?
      # No record came back. Leave the row untouched and mark the attempt.
      field "sync", "skipped — no record returned"
      bullet "The existing CRM data is retained; a failed lookup is not new information."
      crm[ein] = record.merge("last_sync_attempt_at" => Time.now.utc.iso8601)
      next
    end

    merged = merge(record, nonprofit)

    # A verification timestamp, so downstream code can tell fresh rows from rows
    # nobody has touched since import.
    row = merged.row.merge(
      "verified_at" => Time.now.utc.iso8601,
      "verification_request_id" => result.request_id,
      "verification_report_date" => nonprofit.report_date
    )

    crm[ein] = row

    field "fields updated", merged.updates.size
    merged.updates.each { |key, before, after| bullet "#{key}: #{render(before)} → #{render(after)}" }

    field "fields left alone", merged.skipped.size
    merged.skipped.each { |key, reason| bullet "#{key}: kept #{render(record[key])} (#{reason})" }

    field "verified_at", row["verified_at"]
    field "previous verified_at", record["verified_at"]
  end

  heading "CRM after synchronization"

  crm.each do |ein, record|
    puts "  #{ein}  #{record["organization_name"]}"
    puts "    aka=#{render(record["organization_name_aka"])}  city=#{render(record["city"])}  " \
         "zip=#{render(record["zip"])}  bmf=#{render(record["bmf_status"])}"
    puts "    profile=#{render(record["pactman_org_url"])}"
    puts "    verified_at=#{render(record["verified_at"])}"
  end
end

note "Storing `verified_at` is what makes this data auditable. Without it, a row that\n" \
     "was checked yesterday and a row imported from a spreadsheet in 2019 look\n" \
     "identical — and only one of them is evidence."
