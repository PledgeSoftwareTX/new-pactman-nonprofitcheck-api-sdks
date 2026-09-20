# frozen_string_literal: true

# EX-02 — EIN normalization before a single check.
#
# An EIN arrives from an onboarding form with a hyphen and stray whitespace. The
# SDK normalizes it to nine digits before building the request URL; the original
# input is kept locally so support can see exactly what the applicant typed.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_02_ein_normalization.rb

require_relative "lib/client"
require_relative "lib/fixture_api"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

client = ExampleClient.create_client
public_charity = FixtureApi::EINS[:public_charity]

# What a form actually submits, versus what the endpoint expects.
submitted = "  #{public_charity[0, 2]}-#{public_charity[2..]}  "

heading "Normalization"
field "as submitted", submitted.inspect
field "EIN.valid?", NCP::EIN.valid?(submitted)
field "normalized", NCP::EIN.normalize(submitted)
field "hyphenless input", NCP::EIN.normalize(public_charity)

# Both inputs address the same organization, so they are the same request.
field "same request", NCP::EIN.normalize(submitted) == NCP::EIN.normalize(public_charity)

# Keep the raw input alongside the normalized value for local diagnostics. Store
# the normalized form as your key — that is what the API echoes back.
applicant = { ein_as_submitted: submitted, ein: NCP::EIN.normalize(submitted) }

# `check` normalizes internally too, so passing the raw string is safe. Doing it
# up front means your own records and the API's agree on one canonical value.
result = client.nonprofits.check(applicant[:ein_as_submitted])

heading "Response"
field "EIN in request", applicant[:ein]
field "EIN in response", result.nonprofit&.ein
field "organization_name", result.nonprofit&.organization_name

note "Normalization is a formatting step. A nine-digit value is not evidence that an\n" \
     "organization exists, is tax-exempt, or is in good standing."
