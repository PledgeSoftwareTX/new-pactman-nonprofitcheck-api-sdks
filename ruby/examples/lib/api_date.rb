# frozen_string_literal: true

require "time"

# Reading the API's timestamps.
#
# Every date on a response is formatted `M/DD/YYYY h:mm:ss AM`, with no zone. The
# SDK hands it over as the String it arrived as; turning it into a `Time` is the
# caller's step, and a step with a format, because `Time.parse` guesses —
# `3/05/2026` is the fifth of March here and could be the third of May elsewhere.
module ApiDate
  FORMAT = "%m/%d/%Y %I:%M:%S %p"

  module_function

  # The timestamp as a local `Time`, or `nil` when there is none to read.
  def parse(value)
    return nil unless value.is_a?(String) && !value.strip.empty?

    text = value.tr("  ", "  ").delete(",")

    begin
      Time.strptime(text, FORMAT)
    rescue ArgumentError
      begin
        Time.iso8601(text)
      rescue ArgumentError
        nil
      end
    end
  end

  # Whole days from `time` to `now`.
  def age_in_days(time, now = Time.now)
    ((now - time) / 86_400).round
  end
end
