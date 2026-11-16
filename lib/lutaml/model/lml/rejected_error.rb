# frozen_string_literal: true

module Lutaml
  module Model
    module Lml
      # A named rejection from the exporter or the document validator:
      # the construct is constructor-contract, not schema, or the
      # document does not meet the agreed contract (lutaml-model#1033).
      class RejectedError < StandardError
        # The full error catalogue of the agreed contract. The exporter
        # raises the export-side codes; DocumentValidator raises the
        # document-side codes; importer/generator/gate cards raise the
        # remainder (missing_type_binding, round_trip_mismatch,
        # checksum_mismatch, capability_missing, nonterminating_rational).
        CODES = %i[
          unsupported_version invalid_document duplicate_id
          dangling_reference unknown_type unsupported_type
          missing_type_binding unsupported_format unsupported_mapping
          non_serializable_default lambda_default custom_initialize
          imperative_element_order invalid_ordered_content reserved_member
          nonterminating_rational unknown_discriminator round_trip_mismatch
          checksum_mismatch capability_missing not_serializable
        ].freeze

        # Value rendering for detail strings. Hash#inspect changed format
        # in Ruby 3.4, so containers are spelled here and the same
        # rejection reads identically on every Ruby.
        def self.show(value)
          case value
          when ::Hash then "{#{value.map { |k, v| "#{show(k)} => #{show(v)}" }.join(', ')}}"
          when ::Array then "[#{value.map { |item| show(item) }.join(', ')}]"
          else value.inspect
          end
        end

        attr_reader :reason, :klass, :detail, :location, :model_id,
                    :attribute, :format, :rule

        # True when the rejection came from reading a document in (import,
        # parse, materialise) rather than writing one out.
        def import?
          @import
        end

        # +reason+ is one of CODES (legacy callers pass the export-side
        # subset). +klass+ and +detail+ keep their legacy meaning; the
        # keywords locate a validator finding: +location+ is a JSON
        # pointer into the document, +model_id+ the "Name@register" ID.
        def initialize(reason, klass = nil, detail = nil, location: nil,
                       model_id: nil, attribute: nil, format: nil, rule: nil,
                       import: false)
          @reason = reason
          @klass = klass
          @detail = detail
          @location = location
          @model_id = model_id
          @attribute = attribute
          @format = format
          @rule = rule
          @import = import
          message = if klass && import then "cannot import #{klass} from LML: #{reason}"
                    elsif klass then "cannot export #{klass} to LML: #{reason}"
                    else "invalid LML: #{reason}"
                    end
          message += " (#{detail})" if detail
          message += " at #{location}" if location
          super(message)
        end

        # The same rejection worded for the import side.
        def as_import
          return self if import?

          self.class.new(reason, klass, detail, location: location, model_id: model_id,
                                                attribute: attribute, format: format, rule: rule,
                                                import: true)
        end
      end
    end
  end
end
