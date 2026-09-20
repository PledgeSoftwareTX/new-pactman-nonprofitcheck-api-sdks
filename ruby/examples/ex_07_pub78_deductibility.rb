# frozen_string_literal: true

# EX-07 — Publication 78 and deductibility review.
#
# Publication 78 is the IRS list of organizations eligible to receive
# tax-deductible charitable contributions, together with the limitation that
# applies. A donation or grant workflow reads it to decide what to tell a donor —
# and the deciding is the workflow's job, not the SDK's.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_07_pub78_deductibility.rb [EIN]

require_relative "lib/client"
require_relative "lib/fixture_api"
require_relative "lib/irs_codes"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

client = ExampleClient.create_client
ein = ARGV.fetch(0, FixtureApi::EINS[:public_charity])

nonprofit = client.nonprofits.check(ein).nonprofit

if nonprofit.nil?
  puts "No record for EIN #{ein}."
  exit 0
end

pub78 = NCP::Sources.pub78(nonprofit)

if pub78.nil?
  puts "The response carried no Publication 78 data for this organization."
  exit 0
end

heading "Publication 78 verification"
field "pub78_verified", returned(pub78, :verified)
field "pub78_organization_name", returned(pub78, :organization_name)
field "pub78_ein", returned(pub78, :ein)
field "pub78_city", returned(pub78, :city)
field "pub78_state", returned(pub78, :state)
field "pub78_indicator", returned(pub78, :indicator)
field "pub78_church_message", returned(pub78, :church_message)
field "most_recent_pub78", returned(pub78, :most_recent)

heading "Deductibility entries"

types = pub78.organization_types || []

if types.empty?
  puts "  No deductibility entries were returned."
else
  # An entry can itself be nil where Publication 78 has a row the API could not
  # resolve, so read through it rather than into it.
  types.each_with_index do |entry, index|
    status = IrsCodes.describe_deductibility_status(entry&.deductibility_status_description)

    puts "  [#{index}]"
    field "  deductibility_status_description", status.summary, 34
    field "  deductibility_limitation", entry&.deductibility_limitation, 34
    field "  organization_type", entry&.organization_type, 34
  end
end

# Your policy, expressed against the source data. Change the predicate, not the
# SDK — nothing here is a verdict the API handed down.
heading "Applying a donation policy"

policy = { requires_pub78_listing: true, accepted_deductibility_limitations: %w[50% 60%] }

limitations = types.filter_map { |entry| entry&.deductibility_limitation }
listed = pub78.verified == true
limitation_accepted = limitations.intersect?(policy[:accepted_deductibility_limitations])

bullet "listed in Publication 78: #{listed}"
bullet "limitations returned: #{limitations.empty? ? "none" : limitations.join(", ")}"
bullet "limitation accepted by this policy: #{limitation_accepted}"

field "policy outcome",
      if listed && limitation_accepted
        "eligible under this application's own donation policy"
      else
        "route to review — this application's policy is not satisfied by the returned data"
      end

note "The SDK maps Publication 78 data and stops there. Whether a classification\n" \
     "satisfies your donor communications, your grant agreement, or your tax\n" \
     "reporting obligations is a determination for your own counsel."
