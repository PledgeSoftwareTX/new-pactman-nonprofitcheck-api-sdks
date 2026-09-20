# frozen_string_literal: true

require_relative "test_helper"

# `response_contract.json` restates, in the token vocabulary the live smoke test
# speaks, what the field declarations in `models.rb` say. Two files saying the
# same thing can disagree, and a contract that has drifted from the models it
# claims to mirror would check a live deployment against a promise the gem no
# longer makes.
#
# These tests hold them together: same fields, and every token justified by the
# declared type. Declaring a field on `Nonprofit` fails here until the contract
# learns about it, which is the point — a new field is a new prediction.
class ResponseContractTest < Minitest::Test
  include TestSupport

  CONTRACT = JSON.parse(File.read(File.expand_path("../lib/pactman/nonprofit_check_plus/response_contract.json",
                                                   __dir__)))

  # Each contract section and the model it restates.
  SHAPES = {
    "envelope" => NCP::ApiEnvelope,
    "errorDetail" => NCP::ApiErrorDetail,
    "nonprofit" => NCP::Nonprofit,
    "organizationType" => NCP::OrganizationType
  }.freeze

  STRING_TOKENS = %w[string text date date:iso url ofac-sentence empty].freeze

  # The token kinds a field declaration permits.
  def permitted_by(field)
    kinds = field.types.map do |type|
      if type == String then "string"
      elsif type == :boolean then "boolean"
      elsif type.is_a?(Array) || type == Array then "array"
      elsif type.is_a?(Class) && type <= Numeric then "number"
      elsif type == Hash || (type.is_a?(Class) && type < NCP::Model) then "object"
      else flunk "#{field.name} declares a type the contract has no token for: #{type.inspect}"
      end
    end

    kinds << "null" if field.nullable
    kinds
  end

  def justified?(token, permitted)
    return permitted.include?("string") if STRING_TOKENS.include?(token) || token.start_with?("digits:")

    permitted.include?(token)
  end

  def test_each_section_predicts_exactly_the_fields_its_model_declares
    SHAPES.each do |section, model|
      refute_empty model.fields, "#{model} declares no fields"
      assert_equal model.fields.keys.sort, CONTRACT.fetch(section).keys.sort, "#{section} vs #{model}"
    end
  end

  def test_every_token_is_justified_by_the_declared_type
    SHAPES.each do |section, model|
      CONTRACT.fetch(section).each do |name, allowed|
        field = model.fields.fetch(name)
        permitted = permitted_by(field)

        allowed.split("|").each do |token|
          assert justified?(token, permitted),
                 "#{model}.#{name} is declared #{field.types.inspect} (null: #{field.nullable}), " \
                 "which permits no #{token} value"
        end
      end
    end
  end

  def test_marks_a_field_nullable_exactly_when_the_model_does
    SHAPES.each do |section, model|
      CONTRACT.fetch(section).each do |name, allowed|
        assert_equal model.fields.fetch(name).nullable, allowed.split("|").include?("null"),
                     "#{model}.#{name} is declared null: #{model.fields.fetch(name).nullable} " \
                     "but the contract says #{allowed}"
      end
    end
  end

  def test_requires_exactly_the_fields_the_model_declares_required
    SHAPES.each do |section, model|
      declared = model.fields.values.select(&:required).map(&:name).sort

      assert_equal declared, CONTRACT.fetch("required").fetch(section, []).sort, section
    end
  end

  def test_every_declared_field_has_a_reader_that_returns_the_wire_value
    SHAPES.each_value do |model|
      model.fields.each_value do |field|
        instance = model.new({ field.name => "wire value" })

        assert_equal "wire value", instance.public_send(field.reader), "#{model}##{field.reader}"
      end
    end
  end
end
