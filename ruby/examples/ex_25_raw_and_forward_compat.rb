# frozen_string_literal: true

# EX-25 — Raw response and forward compatibility.
#
# The model and the raw envelope are both available, and the raw one is not a
# debugging afterthought. When the API adds a field, the gem you have installed
# keeps working and the new field is readable immediately — no upgrade, no
# deserialization failure, no dropped data.
#
# The fixture used here is an approved response from a newer API version. It
# carries fields this SDK has never heard of and an enum value outside the
# documented set.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_25_raw_and_forward_compat.rb

require_relative "lib/fixture_api"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

# Documented foundation types. Anything else is unknown, not wrong.
KNOWN_FOUNDATION_TYPES = %w[pc pf po].freeze

FixtureApi.with_fixture_api do |client|
  result = client.nonprofits.check(FixtureApi::EINS[:future_fields])
  nonprofit = result.nonprofit

  if nonprofit.nil?
    puts "No record returned."
    next
  end

  bmf = NCP::Sources.bmf(nonprofit)
  pub78 = NCP::Sources.pub78(nonprofit)

  # Known fields read exactly as they always have.
  heading "Known fields are unaffected"
  field "ein", nonprofit.ein
  field "organization_name", nonprofit.organization_name
  field "bmf_status", returned(bmf, :status)
  field "pub78_verified", returned(pub78, :verified)
  field "subsection_description", returned(bmf, :subsection_description)

  # Unknown fields ride along on the same object. No cast, no upgrade.
  unknown_fields = nonprofit.keys - FixtureApi.known_nonprofit_fields

  heading "Fields this SDK version does not declare"
  field "count", unknown_fields.size

  unknown_fields.each { |key| bullet "#{key} = #{JSON.generate(nonprofit[key])}" }

  # Declared fields have readers; undeclared ones are reached with `[]`, which
  # returns whatever the JSON held, so check what you got before you use it.
  registration = nonprofit["state_charity_registration_status"]

  field "read with []", registration.is_a?(String) ? registration : "<not a String>"
  field "responds to a reader", nonprofit.respond_to?(:state_charity_registration_status)

  # An unknown value in a known field. This is the one that breaks applications
  # that map eagerly into an enum and default the miss.
  heading "An unrecognized value in a documented field"

  foundation_type = bmf&.foundation_type_code

  field "foundation_type_code", foundation_type
  field "in the documented set", KNOWN_FOUNDATION_TYPES.include?(foundation_type)
  field "foundation_type_description", returned(bmf, :foundation_type_description)
  field "handled as",
        if KNOWN_FOUNDATION_TYPES.include?(foundation_type)
          "a known classification"
        else
          "unknown — routed to review, not defaulted to a known type"
        end

  # Nested objects keep their unknown members too.
  first_type = pub78&.organization_types&.first

  heading "Unknown members inside a known object"
  field "deductibility_limitation", returned(first_type, :deductibility_limitation)
  field "deductibility_status_description", returned(first_type, :deductibility_status_description)
  field "future_deductibility_note", returned(first_type, :future_deductibility_note)

  # And the whole envelope, as parsed.
  heading "The raw envelope"
  field 'raw["code"]', result.raw["code"]
  field 'raw["message"]', result.raw["message"]
  field 'raw["timeTaken"]', result.raw["timeTaken"]
  field 'raw["nonprofit_check_count"]', result.raw["nonprofit_check_count"]
  field 'raw["data"] is the record', result.raw["data"].equal?(nonprofit.to_h)
  field "top-level envelope keys", result.raw.keys.join(", ")

  bullet "Persist `raw` when you need to prove later what the API actually said."
  bullet "It is the parsed body, unmodified — nothing was dropped on the way through."
end

note "Forward compatibility cuts both ways: an unknown value must never be coerced\n" \
     "into a known one. \"I do not recognize this\" is a valid, and usually safer,\n" \
     "outcome than a confident wrong answer."
