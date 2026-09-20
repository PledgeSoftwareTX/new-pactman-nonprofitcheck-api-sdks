# frozen_string_literal: true

require "json"

# Signatures of a JSON response, and the differences between two of them.
#
# A recorded copy of a live response is worthless as a drift detector: every run
# returns a fresh `report_date`, a different `timeTaken` and a usage counter that
# only goes up, so a byte comparison fails for reasons that have nothing to do
# with the API changing. What is stable is the shape — which fields exist, what
# type each carries, and what form its values take. That is what a signature
# captures, and comparing one against a recorded baseline is how `smoke_live.rb`
# answers "has the API changed?" without re-recording every time the IRS data
# behind an organization is refreshed.
#
# A signature is a flat, sorted Hash of path to type token:
#
#   {
#     "code" => "number",
#     "data.ein" => "digits:9",
#     "data.most_recent_bmf" => "date",
#     "data.organization_types[].deductibility_limitation" => "text",
#     "data.pub78_verified" => "boolean",
#     "data.revocation_code" => "null",
#     "errors" => "null"
#   }
#
# Flat, so a field that appears, disappears or changes type is one line in a git
# diff, and so comparing two signatures is a key-by-key walk rather than a
# recursive descent that has to re-derive structure it already knows.
#
# The two halves are compared separately — {schema_diff} over the paths,
# {type_diff} over the tokens — because they fail for different reasons and mean
# different things. A field that disappeared breaks callers that read it; a field
# that changed type breaks callers that parse it. Reporting them as one number
# would say only that something moved.
#
# Tokens
#   object, array, boolean, number, null   the JSON type, structural
#   date            `M/D/YYYY h:mm:ss AM` — the format every API timestamp uses
#   date:iso        an ISO-8601 timestamp, which this API does not currently send
#   digits:9        a string of digits, grouped by length: "411787097" is
#                   digits:9, "01085-2643" is digits:5-4, "00" is digits:2
#   url             an http(s) URL
#   ofac-sentence   the SDN sentence `ofac_status` carries, in either wording
#   empty           an empty or whitespace-only string
#   text            any other string
#
# A path that carries more than one token across a single response — a field
# that is a date on one organization in a bulk batch and null on another —
# records them sorted and joined by "|", as in `date|null`.
#
# Only shapes go in. No value from the response is ever recorded, so a baseline
# is safe to commit and a diff is safe to print.
#
# The token vocabulary and every rule below are shared with the Node.js, Python,
# .NET, Java and Go SDKs, so a baseline recorded by one reads the same in all.
module Contract
  # The format every timestamp in this API uses. See `Fixtures.api_date`.
  API_DATE = %r{\A\d{1,2}/\d{1,2}/\d{4},? \d{1,2}:\d{2}:\d{2} ?(?:AM|PM)\z}i

  ISO_DATE = /\A\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}|\z)/

  # Digits, optionally in hyphen-separated groups: EINs, ZIPs, IRS codes.
  DIGIT_GROUPS = /\A\d+(?:-\d+)*\z/

  URL_LIKE = %r{\Ahttps?://}i

  # The clause both OFAC wordings share.
  #
  # Matching the clause rather than either whole sentence keeps a genuine change
  # of wording visible — it would fall back to `text` — while a subject that goes
  # from "was NOT included" to "may be included", or a possible match whose UID
  # differs, stays the same shape. That is a change in the data, not the contract.
  OFAC_SENTENCE = /Specially Designated Nationals ?\(SDN\) list/i

  # Removals first: a field that disappeared breaks callers that read it.
  CHANGE_ORDER = { removed: 0, changed: 1, added: 2 }.freeze

  MARKS = { removed: "-", changed: "~", added: "+" }.freeze

  # String tokens `string` stands for, when the package claims no format.
  STRING_TOKENS = %w[text date date:iso url ofac-sentence empty].freeze

  module_function

  # Classifies a string by the form of its value, never by the value itself.
  def format_of(value)
    # Some formatters write times with a narrow no-break space; the API sends a
    # plain one. Normalize so the same timestamp is not two different tokens.
    text = value.tr("  ", "  ")

    return "empty" if text.strip.empty?
    return "date" if API_DATE.match?(text)
    return "date:iso" if ISO_DATE.match?(text)
    return "digits:#{text.split("-").map(&:length).join("-")}" if DIGIT_GROUPS.match?(text)
    return "url" if URL_LIKE.match?(text)
    return "ofac-sentence" if OFAC_SENTENCE.match?(text)

    "text"
  end

  def token_for(value)
    case value
    when nil then "null"
    when Array then "array"
    when String then format_of(value)
    when Hash then "object"
    when true, false then "boolean"
    when Numeric then "number"
    else value.class.name.downcase
    end
  end

  # Builds the signature of a parsed JSON response.
  def signature_of(value)
    tokens = Hash.new { |hash, path| hash[path] = [] }

    collect(value, "", tokens)

    tokens.sort_by(&:first).to_h { |path, seen| [path, seen.uniq.sort.join("|")] }
  end

  def collect(value, path, tokens)
    tokens[path] << token_for(value) unless path.empty?

    case value
    when Array
      # Every element of an array contributes to one path, so a batch of ten
      # organizations describes one record shape rather than ten.
      value.each { |item| collect(item, "#{path}[]", tokens) }
    when Hash
      value.each { |key, child| collect(child, path.empty? ? key.to_s : "#{path}.#{key}", tokens) }
    end
  end

  # Fields the API stopped sending, and fields it started sending.
  #
  # Additions count. A field the API added is forward-compatible for a caller —
  # the SDK surfaces it through `[]` either way — but it is still the API
  # changing, and a baseline that quietly absorbs additions cannot tell you when
  # it did.
  def schema_diff(baseline, current)
    changes = baseline.filter_map { |path, token| { kind: :removed, path:, token: } unless current.key?(path) } +
              current.filter_map { |path, token| { kind: :added, path:, token: } unless baseline.key?(path) }

    { changes: sort_changes(changes), total: changes.size }
  end

  # Fields whose type or value format changed, across the paths both signatures
  # have. Paths only one of them has are {schema_diff}'s to report, so a single
  # renamed field is one failure rather than two.
  def type_diff(baseline, current)
    changes = baseline.filter_map do |path, token|
      { kind: :changed, path:, from: token, to: current[path] } if current.key?(path) && current[path] != token
    end

    { changes: sort_changes(changes), total: changes.size }
  end

  # The recording held against a live response, with the differences a recording
  # cannot speak to left out.
  #
  # A baseline is one organization's response on one afternoon, so much of what
  # separates it from today's run is not the API moving — it is a different
  # subject, or the same subject whose Pub 78 row lapsed since. Two kinds of
  # difference fall out of that, and neither is drift.
  #
  # Nullability. `pub78_city` was `text` when the recording was made and is
  # `null` now. The field is still there and still declared nullable; this
  # organization simply has no Pub 78 city. Only a move between two forms a value
  # actually took — `digits:9` to `text` — says the API changed.
  #
  # Reachability. `organization_types` arrived null, so the paths beneath it had
  # nowhere to be and read as removed. {coverage_diff} already excuses that
  # against the contract; a recording needs it in both directions, because which
  # side has the populated parent is an accident of which ran first.
  #
  # Both are counted rather than dropped, so a green run still says how much it
  # passed over. What the recording cannot answer, the contract checks do.
  def baseline_diff(before, current)
    changes = []
    nullable = 0
    unreachable = 0

    before.each do |path, token|
      if current.key?(path)
        next if current[path] == token

        if nullability_only?(token, current[path])
          nullable += 1
        else
          changes << { kind: :changed, path:, from: token, to: current[path] }
        end
      elsif unreachable_in?(path, current)
        unreachable += 1
      else
        changes << { kind: :removed, path:, token: }
      end
    end

    current.each do |path, token|
      next if before.key?(path)

      if unreachable_in?(path, before)
        unreachable += 1
      else
        changes << { kind: :added, path:, token: }
      end
    end

    { changes: sort_changes(changes), total: changes.size, nullable:, unreachable: }
  end

  # Whether two tokens differ only over whether a value arrived.
  #
  # Drop `null` from both sides and compare what is left. `date` against
  # `date|null` leaves the same form on each. `date` against `null` leaves one
  # side with nothing, and a side that recorded no form makes no claim about the
  # form. `digits:9` against `text` leaves two different forms, which is drift.
  def nullability_only?(before, after)
    left = without_null(before)
    right = without_null(after)

    left.empty? || right.empty? || left == right
  end

  def without_null(token)
    token.split("|").reject { |one| one == "null" }
  end

  def sort_changes(changes)
    changes.sort_by { |change| [CHANGE_ORDER.fetch(change[:kind]), change[:path]] }
  end

  # "2 removed, 1 added" — the counts that are not zero.
  def summarize_changes(changes)
    counts = CHANGE_ORDER.keys.to_h { |kind| [kind, changes.count { |change| change[:kind] == kind }] }
    parts = counts.select { |_kind, count| count.positive? }.map { |kind, count| "#{count} #{kind}" }

    parts.empty? ? "no differences" : parts.join(", ")
  end

  # One line per change, indented to sit under a check's own line.
  #
  # Every change, with nothing elided. A run that says a field moved and then
  # hides which one sends you back to the deployment to find out by hand.
  def format_changes(changes, indent: "      ")
    changes.map do |change|
      if change[:kind] == :changed
        "#{indent}~ #{change[:path]}: #{change[:from]} → #{change[:to]}"
      else
        "#{indent}#{MARKS.fetch(change[:kind])} #{change[:path]} (#{change[:token]})"
      end
    end.join("\n")
  end

  # --- the package's own prediction -------------------------------------------
  #
  # Everything above compares one live response against another recorded
  # earlier, which answers "did the API move?" but never "does the API still
  # match what this gem tells its users?". The second question is the one with a
  # caller on the other end of it: `models.rb` declares `bmf_status` a boolean,
  # and a user writes `if bmf.status` on the strength of that. Nothing in a
  # self-recorded baseline can notice when the API disagrees, because the
  # baseline is the API's own output — it agrees with itself by construction.
  #
  # `response_contract.json` is the other side of that comparison: the shape this
  # gem predicts, in the same token vocabulary as a signature, so the two can be
  # held against each other directly.

  def string_token?(token)
    STRING_TOKENS.include?(token) || token.start_with?("digits:")
  end

  # Whether an observed token is one the contract allows.
  #
  # `string` is a wildcard over every string token, because a declared String
  # makes no claim about the form of the value. Where the gem does make one — an
  # EIN is nine digits, a timestamp is `M/D/YYYY h:mm:ss AM` — the contract names
  # that token instead, and a value that stops matching it fails even though it
  # is still, technically, a string.
  def permits?(allowed, token)
    tokens = allowed.split("|")

    tokens.include?(token) || (tokens.include?("string") && string_token?(token))
  end

  # The flat expected signature for one endpoint, built from the shared parts.
  #
  # The record is described once and used for both endpoints, so single and bulk
  # cannot drift apart in the contract the way they can on the wire.
  def compose_expected(contract, kind)
    single = kind.to_s == "single"
    prefix = single ? "data." : "data[]."

    expected = contract.fetch("envelope").merge(
      "data" => single ? "null|object" : "array|null",
      "errors[]" => "object",
      "errors[].eins[]" => "string"
    )

    contract.fetch("errorDetail").each { |field, token| expected["errors[].#{field}"] = token }
    expected["data[]"] = "object" unless single
    contract.fetch("nonprofit").each { |field, token| expected["#{prefix}#{field}"] = token }

    # Nullable elements, not just a nullable array: the API sends a null in the
    # list where Publication 78 has a deductibility row it cannot resolve.
    expected["#{prefix}organization_types[]"] = "null|object"

    contract.fetch("organizationType").each do |field, token|
      expected["#{prefix}organization_types[].#{field}"] = token
    end

    expected.sort.to_h
  end

  # Paths the live response carries a value the contract permits no form of.
  #
  # Paths the contract has never heard of are {coverage_diff}'s to report, so a
  # field the API invented is one failure rather than two.
  def contract_diff(expected, observed, _required = nil)
    changes = observed.filter_map do |path, token|
      allowed = expected[path]
      next if allowed.nil?

      offending = token.split("|").reject { |one| permits?(allowed, one) }
      { kind: :changed, path:, from: allowed, to: offending.join("|") } unless offending.empty?
    end

    { changes: sort_changes(changes), total: changes.size }
  end

  # Fields the API sent that the gem does not predict, and fields it predicts
  # that the API did not send.
  #
  # Both directions fail. An unpredicted field is readable only by a caller who
  # already knows to look, and a predicted field that stopped arriving breaks
  # every caller that reads it.
  #
  # The exception is a path that had nowhere to arrive: `errors[].reason` while
  # `errors` is null, `data.organization_types[].organization_type` while that
  # array is null or empty. Those are counted as unreachable.
  #
  # A container that vanished is reported once, at its shallowest path: a `data`
  # that stopped arriving is one failure, not fifty-nine.
  def coverage_diff(expected, observed, required = nil)
    changes = observed.filter_map { |path, token| { kind: :added, path:, token: } unless expected.key?(path) }
    unreachable = 0
    optional_absent = 0

    absent = expected.keys.reject { |path| observed.key?(path) }

    absent.each do |path|
      if unreachable_in?(path, observed)
        unreachable += 1
      elsif ancestors_of(path).any? { |ancestor| absent.include?(ancestor) }
        next
      elsif required && !required.include?(path)
        # A field the models declare optional is permitted to be absent. Without
        # a `required` set every predicted path is treated as required.
        optional_absent += 1
      else
        changes << { kind: :removed, path:, token: expected[path] }
      end
    end

    { changes: sort_changes(changes), total: changes.size, unreachable:, optional_absent: }
  end

  # The paths a response must carry: the structural ones every envelope has, and
  # whatever the models declare `required: true`.
  def required_paths_of(contract, kind)
    single = kind.to_s == "single"
    prefix = single ? "data." : "data[]."
    required = contract.fetch("required", {})

    paths = ["data", "errors[]", "errors[].eins[]", "#{prefix}organization_types[]"]
    paths << "data[]" unless single
    paths.concat(required.fetch("envelope", []))
    paths.concat(required.fetch("errorDetail", []).map { |field| "errors[].#{field}" })
    paths.concat(required.fetch("nonprofit", []).map { |field| "#{prefix}#{field}" })
    paths.concat(required.fetch("organizationType", []).map { |field| "#{prefix}organization_types[].#{field}" })

    paths.to_set
  end

  # Every enclosing path of a signature path, innermost first.
  #
  #   data.organization_types[].organization_type
  #     → data.organization_types[], data.organization_types, data
  def ancestors_of(path)
    ancestors = []
    rest = path

    loop do
      if rest.end_with?("[]")
        rest = rest[0...-2]
      else
        dot = rest.rindex(".")
        return ancestors if dot.nil?

        rest = rest[0...dot]
      end

      ancestors << rest
    end
  end

  # Whether a container above this path arrived in a form with no room for it.
  #
  # A null has no members and an empty array has no elements, so nothing under
  # either was ever going to appear.
  def unreachable_in?(path, observed)
    ancestors_of(path).any? do |ancestor|
      token = observed[ancestor]
      next false if token.nil?

      tokens = token.split("|")

      tokens.all?("null") || (tokens.include?("array") && !observed.key?("#{ancestor}[]"))
    end
  end
end
