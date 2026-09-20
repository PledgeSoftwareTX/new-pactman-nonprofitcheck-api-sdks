# frozen_string_literal: true

# Structural validation of the address an API response carries.
#
# None of this is part of the SDK, and deliberately so. The API reports the
# address IRS records hold; deciding whether that address is good enough to act
# on is a customer policy question.
#
# What this answers: is the returned address *well-formed and self-consistent* —
# are the components that matter present, is `state` a real USPS code, does
# `state_name` agree with it, is `zip` shaped like a ZIP and does it belong to
# the state claimed alongside it.
#
# What this does not answer: whether mail sent there arrives. Deliverability is a
# question for USPS, Lob, Smarty or Google Address Validation, and it needs a
# network call and a second credential. See {Address.validate} for where a
# deliverability verdict would slot in.
#
# Every check is conservative in the same direction: a check that cannot be run
# reports `not_checkable`, never `fail`. An incomplete lookup table here must not
# manufacture a finding about somebody's address.
module Address
  # USPS codes and the state names the API pairs them with.
  US_STATES = {
    "AL" => "Alabama", "AK" => "Alaska", "AZ" => "Arizona", "AR" => "Arkansas",
    "CA" => "California", "CO" => "Colorado", "CT" => "Connecticut", "DE" => "Delaware",
    "DC" => "District of Columbia", "FL" => "Florida", "GA" => "Georgia", "HI" => "Hawaii",
    "ID" => "Idaho", "IL" => "Illinois", "IN" => "Indiana", "IA" => "Iowa",
    "KS" => "Kansas", "KY" => "Kentucky", "LA" => "Louisiana", "ME" => "Maine",
    "MD" => "Maryland", "MA" => "Massachusetts", "MI" => "Michigan", "MN" => "Minnesota",
    "MS" => "Mississippi", "MO" => "Missouri", "MT" => "Montana", "NE" => "Nebraska",
    "NV" => "Nevada", "NH" => "New Hampshire", "NJ" => "New Jersey", "NM" => "New Mexico",
    "NY" => "New York", "NC" => "North Carolina", "ND" => "North Dakota", "OH" => "Ohio",
    "OK" => "Oklahoma", "OR" => "Oregon", "PA" => "Pennsylvania", "RI" => "Rhode Island",
    "SC" => "South Carolina", "SD" => "South Dakota", "TN" => "Tennessee", "TX" => "Texas",
    "UT" => "Utah", "VT" => "Vermont", "VA" => "Virginia", "WA" => "Washington",
    "WV" => "West Virginia", "WI" => "Wisconsin", "WY" => "Wyoming",
    # Territories and military posts. An exempt organization can hold any of these.
    "AS" => "American Samoa", "GU" => "Guam", "MP" => "Northern Mariana Islands",
    "PR" => "Puerto Rico", "VI" => "Virgin Islands",
    "AA" => "Armed Forces Americas", "AE" => "Armed Forces Europe", "AP" => "Armed Forces Pacific"
  }.freeze

  # Leading three ZIP digits each state uses, as inclusive ranges.
  #
  # Illustrative, not the USPS product. A prefix this table does not list makes
  # the ZIP-to-state check `not_checkable`, so omissions cost coverage rather than
  # producing a false finding. Prefixes claimed by more than one state — 06390 on
  # Fishers Island is New York inside Connecticut's range, 340 is a military post
  # inside Florida's — pass for any of their claimants.
  ZIP_PREFIXES = {
    "AL" => [350..369], "AK" => [995..999], "AZ" => [850..865], "AR" => [716..729],
    "CA" => [900..961], "CO" => [800..816], "CT" => [60..69], "DE" => [197..199],
    "DC" => [200..200, 202..205, 569..569], "FL" => [320..349],
    "GA" => [300..319, 398..399], "HI" => [967..968], "ID" => [832..838],
    "IL" => [600..629], "IN" => [460..479], "IA" => [500..528], "KS" => [660..679],
    "KY" => [400..427], "LA" => [700..714], "ME" => [39..49], "MD" => [206..219],
    "MA" => [10..27, 55..55], "MI" => [480..499], "MN" => [550..567],
    "MS" => [386..397], "MO" => [630..658], "MT" => [590..599], "NE" => [680..693],
    "NV" => [889..898], "NH" => [30..38], "NJ" => [70..89], "NM" => [870..884],
    "NY" => [5..5, 63..63, 100..149], "NC" => [270..289], "ND" => [580..588],
    "OH" => [430..459], "OK" => [730..731, 734..749], "OR" => [970..979],
    "PA" => [150..196],
    "RI" => [28..29], "SC" => [290..299], "SD" => [570..577], "TN" => [370..385],
    # 733 is Austin, inside Oklahoma's run — the IRS's own service centre sits there.
    "TX" => [733..733, 750..799, 885..885], "UT" => [840..847], "VT" => [50..59],
    "VA" => [201..201, 220..246], "WA" => [980..994], "WV" => [247..268],
    "WI" => [530..549], "WY" => [820..831],
    "AS" => [967..967], "GU" => [969..969], "MP" => [969..969], "PR" => [6..9],
    "VI" => [8..8], "AA" => [340..340], "AE" => [90..98], "AP" => [962..966]
  }.freeze

  # Prefix → every state that claims it, built once from the ranges above.
  PREFIX_OWNERS = ZIP_PREFIXES.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(state, ranges), owners|
    ranges.each { |range| range.each { |prefix| owners[prefix] << state } }
  end.to_h.freeze

  # Values that occupy a field without saying anything.
  #
  # These arrive in real IRS extracts. Left unchecked they read as data: a `city`
  # of `UNKNOWN` is present, is a String, and is not nil.
  PLACEHOLDERS = [
    "N/A", "NA", "N A", "NONE", "NULL", "NIL", "UNKNOWN", "UNK", "TBD",
    "NOT AVAILABLE", "NOT APPLICABLE", "NO ADDRESS", "SAME", "SEE ATTACHED",
    "-", "--", ".", "...", "X", "XX", "XXX", "XXXX", "0", "00", "000"
  ].freeze

  # Street lines that legitimately carry no house number.
  NUMBERLESS_LINES = ["GENERAL DELIVERY", "PO BOX", "POST OFFICE BOX"].freeze

  # Components an address needs before it locates anything.
  REQUIRED_COMPONENTS = %w[address_line1 city state zip].freeze

  # Every component this module looks at, required or not.
  ADDRESS_COMPONENTS = %w[address_line1 address_line2 city state state_name zip].freeze

  Check = Data.define(:id, :label, :outcome, :detail)
  Result = Data.define(:verdict, :checks, :missing, :failures)

  module_function

  def absent?(value)
    value.nil? || value.to_s.strip.empty?
  end

  def squash(value)
    value.to_s.upcase.gsub(/[^A-Z0-9]+/, " ").strip
  end

  # True when a value is present but carries no information.
  def placeholder?(value)
    return false if absent?(value)

    text = value.to_s.strip.upcase
    PLACEHOLDERS.include?(text) || PLACEHOLDERS.include?(squash(text))
  end

  # The five-digit prefix of a ZIP, or `nil` when there is nothing to read.
  def zip5(value)
    return nil if absent?(value)

    digits = value.to_s.gsub(/\D/, "")
    digits.length >= 5 ? digits[0, 5] : nil
  end

  # `["ME"]` for `04856`, `nil` when no state claims the prefix.
  def states_for_zip(value)
    five = zip5(value)
    five && PREFIX_OWNERS[five[0, 3].to_i]
  end

  # Runs every structural check against one returned address.
  #
  # @param record [#[]] anything carrying the six address fields — a `nonprofit`
  #   from `client.nonprofits.check` reads directly.
  # @return [Result] `verdict` is `inconsistent` when a check failed, `incomplete`
  #   when a required component was not returned, and `usable` when neither
  #   happened. It is never `deliverable`: nothing here has asked USPS anything.
  def validate(record)
    value = ->(component) { record&.[](component) }
    checks = []

    # 1. Presence. A component the API did not return has not been confirmed by
    #    anything, which is the same lesson the comparison examples teach.
    missing = REQUIRED_COMPONENTS.select { |component| absent?(value.call(component)) }

    checks << if missing.empty?
                Check.new("required_components", "required components present", "pass", REQUIRED_COMPONENTS.join(", "))
              else
                Check.new("required_components", "required components present", "fail",
                          "not returned: #{missing.join(", ")}")
              end

    # 2. Placeholders. Present, and still empty of meaning.
    placeholders = ADDRESS_COMPONENTS.select { |component| placeholder?(value.call(component)) }

    checks << if placeholders.empty?
                Check.new("no_placeholders", "no placeholder values", "pass", nil)
              else
                Check.new("no_placeholders", "no placeholder values", "fail",
                          placeholders.map { |component| "#{component}=\"#{value.call(component)}\"" }.join(", "))
              end

    # 3. The state code itself.
    state = absent?(value.call("state")) ? nil : value.call("state").to_s.strip.upcase

    checks << if state.nil?
                Check.new("state_code", "state is a USPS code", "not_checkable", "state was not returned")
              elsif US_STATES.key?(state)
                Check.new("state_code", "state is a USPS code", "pass", "#{state} — #{US_STATES[state]}")
              else
                Check.new("state_code", "state is a USPS code", "fail", "\"#{value.call("state")}\" is not a USPS code")
              end

    # 4. state_name against state. Two fields for one fact is two chances to be
    #    wrong, and IRS extracts do disagree with themselves.
    state_name = absent?(value.call("state_name")) ? nil : value.call("state_name").to_s.strip
    expected_name = state && US_STATES[state]

    checks << if state_name.nil? || expected_name.nil?
                Check.new("state_name_agrees", "state_name agrees with state", "not_checkable",
                          state_name.nil? ? "state_name was not returned" : "state is not a known code")
              elsif squash(state_name) == squash(expected_name)
                Check.new("state_name_agrees", "state_name agrees with state", "pass", state_name)
              else
                Check.new("state_name_agrees", "state_name agrees with state", "fail",
                          "state=#{state} implies \"#{expected_name}\", state_name says \"#{state_name}\"")
              end

    # 5. ZIP shape. Five digits, or nine for ZIP+4. Anything else is not a ZIP.
    raw_zip = absent?(value.call("zip")) ? nil : value.call("zip").to_s.strip
    zip_digits = raw_zip.to_s.gsub(/\D/, "")

    checks << if raw_zip.nil?
                Check.new("zip_format", "zip is 5 or 9 digits", "not_checkable", "zip was not returned")
              elsif [5, 9].include?(zip_digits.length)
                Check.new("zip_format", "zip is 5 or 9 digits", "pass", raw_zip)
              else
                Check.new("zip_format", "zip is 5 or 9 digits", "fail",
                          "\"#{raw_zip}\" has #{zip_digits.length} digits")
              end

    # 6. ZIP against state. The check that catches a transcription error no
    #    single-field check can see.
    claimants = states_for_zip(raw_zip)

    checks << if raw_zip.nil? || state.nil?
                Check.new("zip_matches_state", "zip belongs to state", "not_checkable", "zip or state was not returned")
              elsif claimants.nil?
                Check.new("zip_matches_state", "zip belongs to state", "not_checkable",
                          "no state is on file for prefix #{zip5(raw_zip)&.slice(0, 3) || "???"}")
              elsif claimants.include?(state)
                Check.new("zip_matches_state", "zip belongs to state", "pass", "#{zip5(raw_zip)} is a #{state} ZIP")
              else
                Check.new("zip_matches_state", "zip belongs to state", "fail",
                          "#{zip5(raw_zip)} belongs to #{claimants.join("/")}, state says #{state}")
              end

    # 7. The street line. A number, a box, or general delivery.
    line1 = absent?(value.call("address_line1")) ? nil : squash(value.call("address_line1"))

    checks << if line1.nil?
                Check.new("line1_shape", "address_line1 locates a delivery point", "not_checkable",
                          "address_line1 was not returned")
              elsif line1.match?(/\d/) || NUMBERLESS_LINES.include?(line1)
                Check.new("line1_shape", "address_line1 locates a delivery point", "pass", value.call("address_line1"))
              else
                Check.new("line1_shape", "address_line1 locates a delivery point", "fail",
                          "\"#{value.call("address_line1")}\" carries no number, box or general-delivery marker")
              end

    failures = checks.select { |entry| entry.outcome == "fail" }

    # A deliverability verdict from USPS or an equivalent would be folded in
    # here, as one more check. Nothing above has left the process.
    verdict = if failures.any? { |entry| entry.id != "required_components" }
                "inconsistent"
              elsif missing.any?
                "incomplete"
              else
                "usable"
              end

    Result.new(verdict: verdict, checks: checks, missing: missing, failures: failures)
  end

  # True for the one verdict that clears an address for automated use.
  def usable?(verdict)
    verdict == "usable"
  end
end
