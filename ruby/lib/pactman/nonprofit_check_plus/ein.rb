# frozen_string_literal: true

module Pactman
  module NonprofitCheckPlus
    # EIN normalization and validation.
    #
    # Formatting validation only. Passing these checks says nothing about whether
    # an organization is tax-exempt, in good standing, or eligible for anything —
    # only that the value is shaped like an EIN. No IRS prefix rules are applied.
    module EIN
      # Number of digits in an EIN.
      LENGTH = 9

      # Accepted input shapes: nine digits, optionally with the conventional
      # hyphen after the two-digit prefix. Surrounding whitespace is ignored.
      PATTERN = /\A\d{2}-?\d{7}\z/
      private_constant :PATTERN

      # Leading and trailing whitespace, Unicode included — a no-break space
      # pasted from a document is as invisible as an ordinary one.
      SURROUNDING_WHITESPACE = /\A[[:space:]]+|[[:space:]]+\z/
      private_constant :SURROUNDING_WHITESPACE

      class << self
        # Normalizes an EIN to the nine-digit form the API expects.
        #
        # `"41-1787097"` and `"411787097"` both normalize to `"411787097"`.
        #
        # @param input [String]
        # @return [String]
        # @raise [ValidationError] if the value is not shaped like an EIN.
        def normalize(input)
          issue = issue_for(input)

          raise ValidationError.new(issue.message, [issue]) if issue

          canonical(input)
        end

        # Normalizes a collection of EINs, reporting every failure at once.
        #
        # Duplicates are preserved and order is retained; see
        # {NonprofitsResource#check_bulk} for the optional `dedupe:` behaviour.
        #
        # @param inputs [Array<String>]
        # @return [Array<String>]
        # @raise [ValidationError] if any item is not shaped like an EIN. The
        #   error's `issues` identify the failing item by index and original value.
        def normalize_all(inputs)
          issues = []
          normalized = []

          inputs.each_with_index do |input, index|
            issue = issue_for(input, index)

            if issue
              issues << issue
            else
              normalized << canonical(input)
            end
          end

          unless issues.empty?
            positions = issues.map(&:index).join(", ")

            raise ValidationError.new(
              "#{issues.size} of #{inputs.size} EINs are invalid (at index #{positions}). No request was sent.",
              issues
            )
          end

          normalized
        end

        # True when `input` is shaped like an EIN. Never raises.
        #
        # @param input [Object]
        # @return [Boolean]
        def valid?(input)
          issue_for(input).nil?
        end

        private

        def canonical(input)
          trim(input).delete("-")
        end

        def issue_for(input, index = nil)
          at = index.nil? ? "" : " at index #{index}"

          return ValidationIssue.new("EIN#{at} is required.", index, input) if input.nil?

          unless input.is_a?(String)
            return ValidationIssue.new("EIN#{at} must be a String, received #{input.class}.", index, input)
          end

          trimmed = trim(input)

          return ValidationIssue.new("EIN#{at} is empty.", index, input) if trimmed == ""

          return nil if trimmed && PATTERN.match?(trimmed)

          ValidationIssue.new(
            "EIN#{at} must be #{LENGTH} digits, optionally hyphenated as XX-XXXXXXX. " \
            "Received #{(trimmed || input).inspect}.",
            index,
            input
          )
        end

        # `nil` for a string no pattern can be run against: bytes that are not
        # valid in their declared encoding, or an encoding Regexp cannot read.
        def trim(input)
          input.gsub(SURROUNDING_WHITESPACE, "")
        rescue ArgumentError, EncodingError
          nil
        end
      end
    end
  end
end
