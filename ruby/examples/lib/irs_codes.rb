# frozen_string_literal: true

# Local lookup tables for IRS codes the API returns without a description.
#
# The API already describes most classifications for you —
# `subsection_description`, `foundation_code_description`,
# `foundation_type_description`. Prefer those: they come from the source and
# change with it. Only fields returned as a bare code need a table, and a table
# you own is a table you have to maintain.
#
# Two rules make that safe:
#
#   1. Every lookup has an unknown-value fallback that keeps the original code
#      visible, so a value added by the IRS degrades to "code 42, meaning unknown
#      to this application" rather than to `nil` or a wrong label.
#   2. `null` is reported as `null`, never as an unknown code.
#
# Verify these against the current IRS Exempt Organizations Business Master File
# data dictionary and Publication 78 documentation before relying on them for a
# policy decision.

require_relative "print"

module IrsCodes
  # IRS EO BMF `FILING_REQ_CD` — which annual return the organization files.
  FILING_REQUIREMENT = {
    "00" => "No 990 return required",
    "01" => "Form 990 or 990-EZ required",
    "02" => "Form 990-N (e-Postcard) required",
    "03" => "Group return",
    "04" => "Form 990-BL required (black lung trust)",
    "06" => "Not required to file (church)",
    "07" => "Government 501(c)(1)",
    "13" => "Not required to file (religious organization)",
    "14" => "Not required to file (state instrumentality)"
  }.freeze

  # IRS EO BMF `STATUS` — the exemption status the BMF carries.
  EXEMPT_STATUS = {
    "01" => "Unconditional exemption",
    "02" => "Conditional exemption",
    "12" => "Trust described in section 4947(a)(2)",
    "25" => "Organization terminated"
  }.freeze

  # Publication 78 deductibility status codes.
  DEDUCTIBILITY_STATUS = {
    "PC" => "Public charity",
    "POF" => "Private operating foundation",
    "PF" => "Private foundation",
    "SO" => "Supporting organization",
    "SOUNK" => "Supporting organization, type not determined",
    "LODGE" => "Domestic fraternal society",
    "FORGN" => "Foreign organization",
    "GROUP" => "Subordinate organization in a group ruling",
    "EO" => "Exempt organization, other"
  }.freeze

  Lookup = Data.define(:code, :known, :description, :summary)

  module_function

  def describe_filing_requirement(code) = lookup(FILING_REQUIREMENT, code, "filing requirement")
  def describe_exempt_status(code) = lookup(EXEMPT_STATUS, code, "exempt status")
  def describe_deductibility_status(code) = lookup(DEDUCTIBILITY_STATUS, code, "deductibility status")

  def lookup(table, code, label)
    if code.nil? || code.equal?(Print::NOT_RETURNED)
      return Lookup.new(code: code, known: false, description: nil, summary: Print.render(code))
    end

    description = table[code]

    if description.nil?
      # A code this application has never seen. Keep it legible and keep it
      # flagged; do not guess, and do not drop it.
      return Lookup.new(code: code, known: false, description: nil,
                        summary: "#{code} — unrecognized #{label} code, not interpreted")
    end

    Lookup.new(code: code, known: true, description: description, summary: "#{code} — #{description}")
  end

  # `ruling_month` + `ruling_year` as one value, without inventing a date.
  def format_ruling_date(month, year)
    return Print.render(year) if year.nil? || year.equal?(Print::NOT_RETURNED) || year.to_s.empty?

    month.is_a?(String) && !month.empty? ? "#{year}-#{month.rjust(2, "0")}" : year.to_s
  end
end
