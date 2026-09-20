# frozen_string_literal: true

require_relative "test_helper"

class EINTest < Minitest::Test
  include TestSupport

  def test_normalizes_hyphenated_and_bare_eins_to_the_same_value
    assert_equal "411787097", NCP::EIN.normalize("41-1787097")
    assert_equal "411787097", NCP::EIN.normalize("411787097")
  end

  def test_ignores_surrounding_whitespace_including_unicode
    assert_equal "411787097", NCP::EIN.normalize("  41-1787097  ")
    assert_equal "411787097", NCP::EIN.normalize(" 41-1787097\t\n")
  end

  MALFORMED = {
    "eight digits" => "41178709",
    "ten digits" => "4117870971",
    "letters" => "41-178709A",
    "all letters" => "abcdefghi",
    "unsupported punctuation" => "41.1787097",
    "a hyphen in the wrong place" => "4117-87097",
    "spaces inside" => "41 1787097",
    "empty" => "",
    "whitespace only" => "   ",
    "non-ASCII digits" => "٤١١٧٨٧٠٩٧",
    "invalid bytes" => "41178709\xFF".dup.force_encoding(Encoding::UTF_8),
    "nil" => nil,
    "an integer" => 411_787_097,
    "a symbol" => :"411787097"
  }.freeze

  def test_rejects_malformed_input
    MALFORMED.each do |label, value|
      assert_raises(NCP::ValidationError, label) { NCP::EIN.normalize(value) }
      refute NCP::EIN.valid?(value), label
    end
  end

  def test_names_the_offending_value_without_leaking_configuration
    error = assert_raises(NCP::ValidationError) { NCP::EIN.normalize("41178709") }

    assert_includes error.message, "41178709"
    assert_equal :local, error.origin
    assert_equal "41178709", error.issues.first.value
  end

  def test_normalize_all_preserves_order_and_duplicates
    assert_equal %w[411787097 996589560 411787097], NCP::EIN.normalize_all(%w[41-1787097 996589560 411787097])
  end

  def test_normalize_all_identifies_which_item_failed_by_index_and_value
    error = assert_raises(NCP::ValidationError) { NCP::EIN.normalize_all(%w[411787097 nope 996589560 1234]) }

    assert_equal [1, 3], error.issues.map(&:index)
    assert_equal "nope", error.issues.first.value
    assert_includes error.message, "index 1, 3"
  end
end
