# frozen_string_literal: true

# Name and address comparison for the onboarding examples.
#
# None of this is part of the SDK, and deliberately so. The API returns the
# identity IRS records hold; deciding whether "St. Mary's Hosp" and "SAINT MARYS
# HOSPITAL INC" are the same applicant is a customer policy question, and the
# answer differs between a donation platform, a DAF and a payroll-giving system.
#
# The comparisons below are conservative on purpose:
#
#   - punctuation, casing, spacing and common abbreviations are not differences
#   - a value the API did not return is never scored as agreement
#   - the outcome is a routing hint, never a fraud finding
module Matching
  # Legal suffixes that carry no identifying information.
  LEGAL_SUFFIXES = %w[INC INCORPORATED LLC LTD CO CORP CORPORATION].freeze

  # Abbreviations seen in IRS records versus what applicants type.
  ABBREVIATIONS = {
    "&" => "AND", "ASSN" => "ASSOCIATION", "ASSOC" => "ASSOCIATION", "CTR" => "CENTER", "CENTRE" => "CENTER",
    "FDN" => "FOUNDATION", "FND" => "FOUNDATION", "INTL" => "INTERNATIONAL", "NATL" => "NATIONAL",
    "ORG" => "ORGANIZATION", "SOC" => "SOCIETY", "ST" => "SAINT", "UNIV" => "UNIVERSITY", "DEPT" => "DEPARTMENT",
    "MT" => "MOUNT"
  }.freeze

  # Street-type abbreviations, for address lines.
  STREET_TYPES = {
    "STREET" => "ST", "AVENUE" => "AVE", "ROAD" => "RD", "BOULEVARD" => "BLVD", "DRIVE" => "DR", "LANE" => "LN",
    "SUITE" => "STE", "APARTMENT" => "APT", "NORTH" => "N", "SOUTH" => "S", "EAST" => "E", "WEST" => "W",
    "POST OFFICE BOX" => "PO BOX"
  }.freeze

  Candidate = Data.define(:source, :value, :normalized)
  NameComparison = Data.define(:outcome, :matched_field, :submitted, :candidates)
  FieldComparison = Data.define(:outcome, :submitted, :returned)

  module_function

  def words(value)
    value.to_s.upcase.gsub("&", " & ").gsub(/[^A-Z0-9&]+/, " ").split
  end

  # Uppercase, punctuation-free, abbreviation-expanded, suffix-free.
  def normalize_name(value)
    return nil if value.nil?

    expanded = words(value).map { |word| ABBREVIATIONS.fetch(word, word) }
    expanded.pop while expanded.size > 1 && LEGAL_SUFFIXES.include?(expanded.last)
    expanded.join(" ")
  end

  # Uppercase, punctuation-free, street types abbreviated to the USPS short form.
  def normalize_address_line(value)
    return nil if value.nil?

    text = value.to_s.upcase
    STREET_TYPES.each { |long, short| text = text.gsub(/\b#{long}\b/, short) }
    text.gsub(/[^A-Z0-9]+/, " ").strip
  end

  # ZIP+4 and ZIP5 compare on the five-digit prefix.
  def normalize_zip(value)
    return nil if value.nil?

    digits = value.to_s.gsub(/\D/, "")
    digits.empty? ? nil : digits[0, 5]
  end

  # Compares a submitted name against the names the API returned.
  #
  # @param candidates [Hash{String => String, nil}] field name to returned value.
  # @return [NameComparison] `exact`, `normalized`, `mismatch` or `not_returned`,
  #   plus the field that matched and the normalized forms, so a reviewer can see
  #   the reasoning.
  def compare_name(submitted, candidates)
    target = normalize_name(submitted)
    comparable = candidates.compact

    if comparable.empty?
      return NameComparison.new(outcome: "not_returned", matched_field: nil, submitted: target,
                                candidates: [])
    end

    normalized = comparable.map do |source, value|
      Candidate.new(source: source, value: value, normalized: normalize_name(value))
    end

    exact = normalized.find { |entry| entry.value == submitted }
    if exact
      return NameComparison.new(outcome: "exact", matched_field: exact.source, submitted: target,
                                candidates: normalized)
    end

    equivalent = normalized.find { |entry| entry.normalized == target }

    if equivalent
      return NameComparison.new(outcome: "normalized", matched_field: equivalent.source, submitted: target,
                                candidates: normalized)
    end

    NameComparison.new(outcome: "mismatch", matched_field: nil, submitted: target, candidates: normalized)
  end

  # Compares one address component.
  #
  # `not_returned` is its own outcome. Treating an absent city as a matching city
  # is the quiet failure this method exists to prevent.
  def compare_address_field(submitted, returned, normalize = method(:normalize_address_line))
    return FieldComparison.new(outcome: "not_returned", submitted: submitted, returned: returned) if returned.nil?

    if submitted.nil? || submitted.to_s.strip.empty?
      return FieldComparison.new(outcome: "not_submitted", submitted: submitted, returned: returned)
    end

    return FieldComparison.new(outcome: "exact", submitted: submitted, returned: returned) if submitted == returned

    outcome = normalize.call(submitted) == normalize.call(returned) ? "normalized" : "mismatch"
    FieldComparison.new(outcome: outcome, submitted: submitted, returned: returned)
  end

  # True for outcomes that agree, however loosely. Absence never counts.
  def agreement?(outcome)
    %w[exact normalized].include?(outcome)
  end
end
