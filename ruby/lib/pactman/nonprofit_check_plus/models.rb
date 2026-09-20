# frozen_string_literal: true

module Pactman
  module NonprofitCheckPlus
    # Base class for every response model.
    #
    # A model is a view over the parsed JSON, not a copy of it. Field names
    # mirror the wire format exactly, so what you read in the Pactman API
    # reference is what you call in code — no rename table to keep in sync.
    #
    # Every declared field has a reader, and every field — declared or not — is
    # reachable with `[]`. The API omits fields it has no data for, and a field
    # added by a future API version is readable the day it ships, without a
    # deserialization failure or a gem upgrade:
    #
    #   nonprofit.organization_name        # a declared field
    #   nonprofit["some_future_field"]     # anything the API sent
    #   nonprofit.key?("ofac_status")      # returned at all, `null` included?
    #
    # Readers never coerce. A value arrives as the JSON parser produced it, so
    # `nil` and `false` stay distinct wherever the API distinguishes them.
    class Model
      # A declared field: its wire name, the JSON types it may carry, and whether
      # it may be `null` or be absent. {ResponseContractTest} holds these against
      # `response_contract.json`.
      #
      # @api private
      Field = Data.define(:name, :types, :nullable, :required, :reader)

      class << self
        # Fields declared on this model, keyed by wire name.
        #
        # @return [Hash{String => Field}]
        def fields
          @fields ||= {}
        end

        private

        # Declares a field and defines its reader.
        #
        # `types` are the JSON types the field may carry: `String`, `Numeric`,
        # `:boolean`, `Hash`, a model class for an object, or a one-element array
        # such as `[OrganizationType]` for a list of them.
        def field(name, *types, null: false, required: false, reader: name)
          spec = Field.new(name: name.to_s, types: types.freeze, nullable: null, required: required,
                           reader: reader.to_sym)

          fields[spec.name] = spec
          define_method(spec.reader) { read(spec) }
        end
      end

      # @param data [Hash{String => Object}] a parsed JSON object. Held, not copied.
      def initialize(data = {})
        raise ArgumentError, "#{self.class.name} wraps a Hash, received #{data.class}." unless data.is_a?(Hash)

        @data = data
      end

      # The value the API sent for any field, declared or not. `nil` when the
      # field was `null` or was not returned — use {#key?} to tell them apart.
      def [](name)
        @data[name.to_s]
      end

      # True when the API returned the field at all, `null` included.
      def key?(name)
        @data.key?(name.to_s)
      end

      def fetch(name, *default, &)
        @data.fetch(name.to_s, *default, &)
      end

      # @return [Array<String>] every field the API returned, in wire order.
      def keys
        @data.keys
      end

      # The parsed JSON object this model reads from — the same object that sits
      # in the result's `raw`, not a copy.
      #
      # @return [Hash{String => Object}]
      def to_h
        @data
      end

      def to_json(*)
        @data.to_json(*)
      end

      def ==(other)
        other.instance_of?(self.class) && other.to_h == @data
      end
      alias eql? ==

      def hash
        [self.class, @data].hash
      end

      def inspect
        "#<#{self.class.name} #{@data.inspect}>"
      end

      private

      # Wraps a nested object in its model and a list in its element model;
      # returns everything else exactly as parsed.
      def read(spec)
        value = @data[spec.name]

        case value
        when Hash
          model = spec.types.find { |type| type.is_a?(Class) && type < Model }
          model ? model.new(value) : value
        when Array
          list = spec.types.find { |type| type.is_a?(Array) }
          model = list&.first
          return value unless model.is_a?(Class) && model < Model

          value.map { |item| item.is_a?(Hash) ? model.new(item) : item }
        else
          value
        end
      end
    end

    # A deductibility entry from IRS Publication 78.
    class OrganizationType < Model
      field :organization_type, String, null: true
      field :deductibility_limitation, String, null: true
      field :deductibility_status_description, String, null: true
    end

    # A nonprofit record as returned by the US nonprofit check endpoints.
    #
    # Source-specific findings are flat on this object, prefixed by source
    # (`pub78_*`, `bmf_*`, `ofac_*`, and the revocation fields for the IRS
    # Automatic Revocation of Exemption list). See {Sources} for grouped views.
    #
    # Declared here is what the production API returns. Some deployments serve
    # additional source fields — the BMF address (`bmf_city`, `bmf_state`,
    # `bmf_street_address`), `bmf_source_pf_filing_req_cd`,
    # `bmf_deductability_text`, `pub78_source_org_type_1..3`,
    # `ofac_list_published_date` and `aroe_list_published_date`. They are not
    # declared because production does not return them; when it does, they are
    # readable through `[]` and through the result's `raw`, and this gem will
    # declare them in a release of its own.
    class Nonprofit < Model
      # Public Pactman profile URL for the organization.
      field :pactman_org_url, String, null: true
      field :organization_info_last_modified, String, null: true

      field :ein, String, null: true
      field :organization_name, String, null: true
      field :organization_name_aka, String, null: true
      field :address_line1, String, null: true
      field :address_line2, String, null: true
      field :city, String, null: true
      field :state, String, null: true
      field :state_name, String, null: true
      field :zip, String, null: true
      field :filing_req_code, String, null: true

      # IRS Publication 78
      field :pub78_church_message, String, null: true
      field :pub78_organization_name, String, null: true
      field :pub78_ein, String, null: true
      field :pub78_verified, :boolean, null: true
      field :pub78_city, String, null: true
      field :pub78_state, String, null: true
      field :pub78_indicator, String, null: true
      # An entry can itself be `nil`, where Publication 78 has a row the API
      # could not resolve.
      field :organization_types, [OrganizationType], null: true
      field :most_recent_pub78, String, null: true

      # IRS Business Master File
      field :bmf_church_message, String, null: true
      field :bmf_organization_name, String, null: true
      field :bmf_ein, String, null: true
      field :bmf_status, :boolean, null: true
      field :bmf_subsection, String, null: true
      field :most_recent_bmf, String, null: true
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

      # OFAC Specially Designated Nationals finding.
      #
      # The API returns a sentence, not a flag — do not pattern-match it to
      # derive a boolean. Read it, or present it to a reviewer.
      field :ofac_status, String, null: true

      # IRS Automatic Revocation of Exemption
      field :revocation_code, String, null: true
      field :revocation_date, String, null: true
      field :reinstatement_date, String, null: true

      # True when the IRS BMF and Publication 78 records disagree.
      field :irs_bmf_pub78_conflict, :boolean, null: true
      field :report_date, String, null: true
    end

    # One entry from the envelope's `errors` array.
    class ApiErrorDetail < Model
      # The API resource the error came from.
      field :resource, String
      # Human-readable explanation.
      field :reason, String
      # Status code for this specific failure, which may differ from the HTTP status.
      field :code, Numeric
      # EINs this error applies to, for bulk requests.
      field :eins, [String], String
    end

    # The envelope every nonprofit check response is wrapped in.
    #
    # `data` is not declared: each endpoint fills it differently, with one record
    # or a list of them, and the result objects read it for you.
    class ApiEnvelope < Model
      field :code, Numeric
      field :message, String
      # Item-level failures. Present on successful responses too — a bulk request
      # where some EINs were not found returns HTTP 200 with entries here.
      field :errors, [ApiErrorDetail], String, null: true
      # Server-side processing time in milliseconds.
      field :timeTaken, Numeric, null: true, reader: :time_taken
      # Checks the account has consumed so far in the current billing cycle,
      # including this request. It resets when a new cycle begins.
      #
      # This is a running total, not the size of the request you just made.
      field :nonprofit_check_count, Numeric, null: true
    end
  end
end
