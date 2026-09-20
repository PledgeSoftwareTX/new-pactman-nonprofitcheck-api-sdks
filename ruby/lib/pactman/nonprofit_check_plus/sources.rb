# frozen_string_literal: true

module Pactman
  module NonprofitCheckPlus
    # IRS Publication 78 findings.
    class Pub78Source < Model
      field :verified, :boolean, null: true
      field :organization_name, String, null: true
      field :ein, String, null: true
      field :city, String, null: true
      field :state, String, null: true
      field :indicator, String, null: true
      field :church_message, String, null: true
      field :organization_types, [OrganizationType], null: true
      field :most_recent, String, null: true
    end

    # IRS Business Master File findings.
    class BmfSource < Model
      field :status, :boolean, null: true
      field :organization_name, String, null: true
      field :ein, String, null: true
      field :church_message, String, null: true
      field :subsection, String, null: true
      field :subsection_description, String, null: true
      field :foundation_code, String, null: true
      field :foundation_code_description, String, null: true
      field :foundation_type_code, String, null: true
      field :foundation_type_description, String, null: true
      field :foundation_509a_status, String, null: true
      field :ruling_month, String, null: true
      field :ruling_year, String, null: true
      field :group_exemption, String, null: true
      field :exempt_status_code, String, null: true
      field :filing_req_code, String, null: true
      field :most_recent, String, null: true
    end

    # IRS Automatic Revocation of Exemption findings.
    class AroeSource < Model
      field :revocation_code, String, null: true
      field :revocation_date, String, null: true
      field :reinstatement_date, String, null: true
    end

    # OFAC Specially Designated Nationals findings.
    class OfacSource < Model
      # The finding as the API phrases it. This is prose, not a flag; the API
      # does not currently return a boolean match indicator, and this gem does
      # not invent one by matching on the wording.
      field :status, String, null: true
    end

    # Grouped views over the source-specific findings on a {Nonprofit}.
    #
    # These are projections, not derivations: every attribute is copied 1:1 from
    # a field the API returned. Nothing here computes an "approved", "eligible"
    # or "safe" verdict, and nothing infers a value from another field.
    #
    # Each accessor returns `nil` when the API returned no data at all for that
    # source. That keeps "the source was not returned" distinguishable from an
    # explicit negative such as `pub78_verified: false` or a `null` field.
    module Sources
      PUB78 = {
        "verified" => "pub78_verified",
        "organization_name" => "pub78_organization_name",
        "ein" => "pub78_ein",
        "city" => "pub78_city",
        "state" => "pub78_state",
        "indicator" => "pub78_indicator",
        "church_message" => "pub78_church_message",
        "organization_types" => "organization_types",
        "most_recent" => "most_recent_pub78"
      }.freeze

      BMF = {
        "status" => "bmf_status",
        "organization_name" => "bmf_organization_name",
        "ein" => "bmf_ein",
        "church_message" => "bmf_church_message",
        "subsection" => "bmf_subsection",
        "subsection_description" => "subsection_description",
        "foundation_code" => "foundation_code",
        "foundation_code_description" => "foundation_code_description",
        "foundation_type_code" => "foundation_type_code",
        "foundation_type_description" => "foundation_type_description",
        "foundation_509a_status" => "foundation_509a_status",
        "ruling_month" => "ruling_month",
        "ruling_year" => "ruling_year",
        "group_exemption" => "group_exemption",
        "exempt_status_code" => "exempt_status_code",
        "filing_req_code" => "filing_req_code",
        "most_recent" => "most_recent_bmf"
      }.freeze

      AROE = {
        "revocation_code" => "revocation_code",
        "revocation_date" => "revocation_date",
        "reinstatement_date" => "reinstatement_date"
      }.freeze

      OFAC = {
        "status" => "ofac_status"
      }.freeze

      private_constant :PUB78, :BMF, :AROE, :OFAC

      class << self
        # Publication 78 findings, or `nil` if the API returned none.
        #
        # @param nonprofit [Nonprofit, Hash]
        # @return [Pub78Source, nil]
        def pub78(nonprofit)
          project(Pub78Source, nonprofit, PUB78)
        end

        # Business Master File findings, or `nil` if the API returned none.
        #
        # @param nonprofit [Nonprofit, Hash]
        # @return [BmfSource, nil]
        def bmf(nonprofit)
          project(BmfSource, nonprofit, BMF)
        end

        # Automatic Revocation of Exemption findings, or `nil` if the API returned none.
        #
        # @param nonprofit [Nonprofit, Hash]
        # @return [AroeSource, nil]
        def aroe(nonprofit)
          project(AroeSource, nonprofit, AROE)
        end

        # OFAC findings, or `nil` if the API returned none.
        #
        # @param nonprofit [Nonprofit, Hash]
        # @return [OfacSource, nil]
        def ofac(nonprofit)
          project(OfacSource, nonprofit, OFAC)
        end

        private

        # Copies the mapped fields onto a new object, preserving `nil` and `false`,
        # and the values themselves rather than copies of them.
        #
        # Returns `nil` only when every mapped field is absent from the response,
        # which is how "this source was not returned" is represented.
        def project(model, nonprofit, mapping)
          wire = wire_hash(nonprofit)
          projected = {}

          mapping.each do |target, wire_field|
            projected[target] = wire[wire_field] if wire.key?(wire_field)
          end

          projected.empty? ? nil : model.new(projected)
        end

        def wire_hash(nonprofit)
          case nonprofit
          when Nonprofit then nonprofit.to_h
          when Hash then nonprofit.transform_keys(&:to_s)
          else
            raise ArgumentError, "Expected a Nonprofit or a Hash, received #{nonprofit.class}."
          end
        end
      end
    end
  end
end
