# frozen_string_literal: true

require_relative "lib/pactman/nonprofit_check_plus/version"

Gem::Specification.new do |spec|
  spec.name = Pactman::NonprofitCheckPlus::GEM_NAME
  spec.version = Pactman::NonprofitCheckPlus::VERSION
  spec.authors = ["Pactman"]
  spec.license = "MIT"

  spec.summary = "Official Ruby SDK for the Pactman Nonprofit Check Plus API."
  spec.description = "Verify US nonprofits by EIN against IRS BMF, Publication 78, Automatic Revocation " \
                     "and OFAC data. No runtime dependencies."
  spec.homepage = "https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/tree/master/ruby#readme"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/tree/master/ruby",
    "bug_tracker_uri" => "https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/issues",
    "documentation_uri" => "https://pactman.org/nonprofitcheckplus-api/docs",
    "rubygems_mfa_required" => "true"
  }

  spec.required_ruby_version = ">= 3.3"

  # The published gem is the library and nothing else. The examples, the mock
  # server and the live smoke test are in the repository.
  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]
end
