# frozen_string_literal: true

require "json"

# Fixture organizations for the examples and the mock server.
#
# Scenarios like a revoked exemption, an OFAC match, a cross-source conflict or
# an unknown future field cannot be summoned on demand from the production API.
# They are declared here once so an example can demonstrate the handling and the
# mock server can serve the record.
#
# Field names and values mirror the shapes documented in the Pactman API
# reference. The EINs are illustrative and are not real organizations.
module Fixtures
  # The two OFAC sentences the API returns. It reports prose, not a boolean.
  OFAC_NO_MATCH =
    "This organization was NOT included in the Office of Foreign Assets Control Specially Designated Nationals " \
    "(SDN) list."

  OFAC_POSSIBLE_MATCH =
    "This organization may be included in the Office of Foreign Assets Control Specially Designated " \
    "Nationals(SDN) list. A close match was found with the Special Designated National with UID: 41234"

  # Named EINs the examples refer to, so no example hard-codes a bare number.
  EINS = {
    # A 501(c)(3) public charity with every source returned and nothing adverse.
    public_charity: "411787097",
    # A second clean organization, for bulk examples.
    public_charity_second: "996589560",
    # A 501(c)(3) private foundation — different foundation and filing codes.
    private_foundation: "042103594",
    # A record with most optional identity fields returned as null.
    sparse_identity: "060646700",
    # Address fields that are present but disagree with each other.
    inconsistent_address: "311580204",
    # Every source date is old, for the freshness and re-review examples.
    stale_data: "362167048",
    # Listed in the IRS Automatic Revocation of Exemption data, not reinstated.
    revoked: "237112796",
    # Revoked and subsequently reinstated — both dates present.
    reinstated: "133039601",
    # A possible OFAC SDN match.
    ofac_match: "954367818",
    # OFAC screening returned no value for this organization.
    ofac_unavailable: "061553389",
    # BMF and Publication 78 disagree; `irs_bmf_pub78_conflict` is true.
    conflicted: "521693387",
    # Carries fields and an enum value this SDK version does not know about.
    future_fields: "237324370",
    # Production's shape plus the source fields only newer deployments return.
    pending_source_fields: "046001341",
    # Well-formed, but no record exists.
    no_record: "999999999"
  }.freeze

  # EINs the mock server answers with a specific failure, for the error examples.
  CONTROL_EINS = {
    # Always answers HTTP 429 with `Retry-After: 1`.
    rate_limited: "900000429",
    # Answers HTTP 503 twice, then succeeds.
    transient_failure: "900000503",
    # Holds the response open, so a short timeout expires.
    slow: "900000408"
  }.freeze

  DEDUCTIBILITY_PUBLIC_CHARITY = {
    "organization_type" =>
      "Deductions for donations to public charities are generally limited to 50 percent of adjusted gross income " \
      "(AGI). This limit increases to 60% of AGI for cash donations. For Non-Cash assets held for more than one " \
      "year, the limit is 30% of AGI.",
    "deductibility_limitation" => "50%",
    "deductibility_status_description" => "PC"
  }.freeze

  DEDUCTIBILITY_PRIVATE_FOUNDATION = {
    "organization_type" =>
      "Deductions for donations to private foundations are generally limited to 30 percent of adjusted gross " \
      "income (AGI). For Non-Cash assets held for more than one year, the limit is 20% of AGI.",
    "deductibility_limitation" => "30%",
    "deductibility_status_description" => "PF"
  }.freeze

  class << self
    # The API formats every date as `M/DD/YYYY h:mm:ss AM`. Fixture dates are
    # generated relative to today so the freshness examples stay meaningful
    # however long after they were written they are run.
    def api_date(days_ago)
      (Time.now - (days_ago * 86_400)).strftime("%-m/%d/%Y %-l:%M:%S %p")
    end

    # Every organization the mock server can return, keyed by EIN.
    #
    # Built on each call rather than once at load, so a long-running mock server
    # keeps its dates relative to the day it answers.
    def organizations
      [
        public_charity(EINS[:public_charity], "Meals Today Example Nonprofit",
                       "organization_name_aka" => "MEALS TODAY E.N",
                       "pub78_organization_name" => "Meals Today Example Nonprofit, Inc."),

        public_charity(EINS[:public_charity_second], "Aborjaily Example Nonprofit",
                       "organization_name_aka" => "ABORJAILY E.N", "city" => "SPRINGFIELD",
                       "pub78_city" => "Springfield", "zip" => "01103-1420", "address_line1" => "19 HAMPDEN ST",
                       "address_line2" => nil),

        # A private foundation files a 990-PF, so it carries no general 990
        # filing requirement.
        public_charity(EINS[:private_foundation], "Hartwell Family Example Foundation",
                       "organization_name_aka" => nil, "filing_req_code" => "00",
                       "organization_types" => [DEDUCTIBILITY_PRIVATE_FOUNDATION],
                       "subsection_description" => "501(c)(3) Private Foundation", "foundation_code" => "04",
                       "foundation_code_description" => "Private non-operating foundation",
                       "foundation_type_code" => "pf",
                       "foundation_type_description" => "Private non-operating foundation",
                       "foundation_509a_status" => "N/A", "ruling_month" => "11", "ruling_year" => "1998"),

        # Optional identity fields the API had no value for. `null` here means
        # "the API returned no value", which is not the same as "this did not
        # match". And no OFAC key at all: the source was not reported for this
        # organization, which is not the same as a null status or a no-match.
        public_charity(EINS[:sparse_identity], "Quiet Harbor Example Trust",
                       { "organization_name_aka" => nil, "address_line1" => "PO BOX 118", "address_line2" => nil,
                         "city" => "ROCKPORT", "state" => "ME", "state_name" => nil, "zip" => nil,
                         "pub78_city" => nil, "pub78_state" => nil, "group_exemption" => nil,
                         "ruling_month" => nil, "ruling_year" => nil },
                       ["ofac_status"]),

        # Every address component is present, and they contradict one another:
        # the state code says Massachusetts, the state name and the ZIP say
        # Maine, and address_line2 holds a placeholder. Transcription damage of
        # this kind survives any check that only asks whether a field came back.
        public_charity(EINS[:inconsistent_address], "Harbor Light Example Alliance",
                       "organization_name_aka" => nil, "address_line1" => "12 SEA STREET", "address_line2" => "N/A",
                       "city" => "ROCKPORT", "state" => "MA", "state_name" => "Maine", "zip" => "04856",
                       "pub78_city" => "Rockport", "pub78_state" => "MA"),

        # Nothing adverse, but every source is well out of date.
        public_charity(EINS[:stale_data], "Long Quiet Example Foundation",
                       "organization_info_last_modified" => api_date(700), "most_recent_pub78" => api_date(640),
                       "most_recent_bmf" => api_date(610)),

        public_charity(EINS[:revoked], "Lapsed Filings Example Society",
                       "organization_name_aka" => nil, "pub78_verified" => false, "pub78_indicator" => nil,
                       "organization_types" => nil, "bmf_status" => false,
                       "subsection_description" => "501(c)(3) Public Charity", "exempt_status_code" => "25",
                       "revocation_code" => "01", "revocation_date" => api_date(1_260), "reinstatement_date" => nil),

        public_charity(EINS[:reinstated], "Second Chance Example Alliance",
                       "organization_name_aka" => "SECOND CHANCE E.A", "revocation_code" => "01",
                       "revocation_date" => api_date(1_260), "reinstatement_date" => api_date(520)),

        public_charity(EINS[:ofac_match], "Overseas Relief Example Fund",
                       "organization_name_aka" => "OVERSEAS RELIEF E.F", "ofac_status" => OFAC_POSSIBLE_MATCH),

        # The API returned nothing for OFAC. Absent is not the same as "no match".
        public_charity(EINS[:ofac_unavailable], "Riverbend Example Coalition", "ofac_status" => nil),

        # BMF says exempt, Publication 78 does not list the organization, and the
        # API flags the disagreement rather than picking a winner.
        public_charity(EINS[:conflicted], "Crosscheck Example Institute",
                       "organization_name" => "CROSSCHECK EXAMPLE INSTITUTE", "pub78_organization_name" => nil,
                       "pub78_ein" => nil, "pub78_verified" => false, "pub78_city" => nil, "pub78_state" => nil,
                       "pub78_indicator" => nil, "organization_types" => nil, "most_recent_pub78" => api_date(26),
                       "bmf_organization_name" => "CROSSCHECK EXAMPLE INST", "bmf_status" => true,
                       "irs_bmf_pub78_conflict" => true),

        # A response from a newer API version: fields this SDK has never heard
        # of, and an enum value outside the documented set.
        public_charity(EINS[:future_fields], "Forward Compatible Example Trust",
                       "foundation_type_code" => "zz",
                       "foundation_type_description" => "A classification added after this SDK was published",
                       "organization_types" => [
                         DEDUCTIBILITY_PUBLIC_CHARITY.merge(
                           "deductibility_status_description" => "XX",
                           "future_deductibility_note" => "An unknown member of a known object"
                         )
                       ],
                       "state_charity_registration_status" => "ACTIVE",
                       "watchlist_screening" => { "provider" => "example", "matches" => 0,
                                                  "list_published_date" => api_date(5) }),

        # A deployment running ahead of production. Every other fixture is the
        # shape entities.pactman.org returns today; this one adds the ten source
        # fields that are built but not yet released there. This gem deliberately
        # does not declare them (see `Nonprofit` in models.rb), so they exercise
        # the path that keeps undeclared fields readable through `raw` and `[]`.
        public_charity(EINS[:pending_source_fields], "Ahead Of Production Example Fund",
                       "organization_name_aka" => nil, "pub78_source_org_type_1" => "PC",
                       "pub78_source_org_type_2" => nil, "pub78_source_org_type_3" => nil,
                       "bmf_city" => "WESTFIELD", "bmf_state" => "MA", "bmf_street_address" => "50 LOWELL AVE APT 3B",
                       "bmf_source_pf_filing_req_cd" => "0", "bmf_deductability_text" => "Contributions are deductible",
                       "ofac_list_published_date" => api_date(5), "aroe_list_published_date" => api_date(12))
      ].to_h { |organization| [organization["ein"], organization] }
    end

    # Every field this gem predicts on an organization.
    #
    # Read from `response_contract.json` rather than from a fixture, so that what
    # the SDK claims to know is stated in one place. See ex-25: a field outside
    # this set is newer than this SDK, which is not an error, but is worth
    # knowing about.
    def known_nonprofit_fields
      @known_nonprofit_fields ||= JSON.parse(File.read(CONTRACT_PATH)).fetch("nonprofit").keys.freeze
    end

    # True when the mock server has a record for this EIN.
    def fixture?(ein)
      organizations.key?(ein)
    end

    # A fresh copy, so an example mutating a record cannot affect later calls.
    def organization(ein)
      organizations[ein]
    end

    private

    def slug(name)
      name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
    end

    # A complete, unremarkable public charity. Scenarios override from here.
    #
    # `omit` deletes keys outright, so the record can express "the API returned
    # no field at all" as distinct from "the API returned null".
    def public_charity(ein, name, overrides = {}, omit = [])
      organization = {
        "pactman_org_url" => "https://pactman.org/profile/nonprofit/#{slug(name)}-#{ein[-4..]}",
        "organization_info_last_modified" => api_date(40),

        "ein" => ein,
        "organization_name" => name.upcase,
        "organization_name_aka" => nil,
        "address_line1" => "50 LOWELL AVE",
        "address_line2" => "APT 3B",
        "city" => "WESTFIELD",
        "state" => "MA",
        "state_name" => "Massachusetts",
        "zip" => "01085-2643",
        "filing_req_code" => "01",

        "pub78_church_message" => nil,
        "pub78_organization_name" => name,
        "pub78_ein" => ein,
        "pub78_verified" => true,
        "pub78_city" => "Westfield",
        "pub78_state" => "MA",
        "pub78_indicator" => "0",
        "organization_types" => [DEDUCTIBILITY_PUBLIC_CHARITY],
        "most_recent_pub78" => api_date(26),

        "bmf_church_message" => nil,
        "bmf_organization_name" => name.upcase,
        "bmf_ein" => ein,
        "bmf_status" => true,
        "bmf_subsection" => "03",
        "most_recent_bmf" => api_date(20),
        "subsection_description" => "501(c)(3) Public Charity",
        "foundation_code" => "10",
        "foundation_code_description" => "Public charity described in section 509(a)(1) or (2)",
        "foundation_type_code" => "pc",
        "foundation_type_description" => "Public charity described in section 509(a)(1) or (2)",
        "foundation_509a_status" => "N/A",
        "ruling_month" => "07",
        "ruling_year" => "2024",
        "group_exemption" => "0000",
        "exempt_status_code" => "01",

        "ofac_status" => OFAC_NO_MATCH,

        "revocation_code" => nil,
        "revocation_date" => nil,
        "reinstatement_date" => nil,

        "irs_bmf_pub78_conflict" => false,
        "report_date" => api_date(0)
      }.merge(overrides)

      # Round-tripped through JSON so no frozen constant is shared into a record
      # a caller may mutate.
      JSON.parse(JSON.generate(organization.except(*omit)))
    end
  end

  CONTRACT_PATH = File.expand_path("../lib/pactman/nonprofit_check_plus/response_contract.json", __dir__)
end
