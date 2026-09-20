# frozen_string_literal: true

# Console formatting for the examples.
#
# The important rule here is {render}: a field the API returned as `null` and a
# field the API did not return at all print differently. Collapsing them into
# `""` or `"-"` is how a missing value quietly becomes a match.
#
# Ruby has one `nil` for both, so the difference is read where it still exists —
# on the model, with `key?` — by {returned}.
module Print
  # Stands in for a field the API did not send.
  NOT_RETURNED = Object.new.tap do |marker|
    def marker.inspect = "<not returned>"
    def marker.to_s = "<not returned>"
  end.freeze

  module_function

  # The value of `name` on a model, or {NOT_RETURNED} when the model is `nil` or
  # the API sent no such field.
  def returned(model, name)
    model&.key?(name) ? model[name] : NOT_RETURNED
  end

  def heading(text)
    puts "\n#{text}"
    puts "─" * text.length
  end

  # `<null>` for an explicit null, `<not returned>` for an absent field.
  def render(value)
    return "<not returned>" if value.equal?(NOT_RETURNED)
    return "<null>" if value.nil?
    return (value.empty? ? "<empty list>" : "#{value.size} entries") if value.is_a?(Array)

    value.to_s
  end

  def field(label, value, width = 32)
    puts "  #{label.to_s.ljust(width)} #{render(value)}"
  end

  def bullet(text)
    puts "  • #{text}"
  end

  # A short note. Used for policy statements and caveats.
  def note(text)
    puts "\n#{text}"
  end

  # Pretty JSON, indented to sit under a heading.
  def json_block(value, indent: "    ")
    puts JSON.pretty_generate(value).lines.map { |line| "#{indent}#{line}" }.join
  end
end
