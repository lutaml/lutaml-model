# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class RestrictionSimpleType < Base
          attribute :id, :string
          attribute :base, :string
          attribute :annotation, :annotation
          attribute :simple_type, :simple_type
          attribute :length, :length, collection: true, initialize_empty: true
          attribute :pattern, :pattern, collection: true, initialize_empty: true
          attribute :min_length, :min_length, collection: true,
                                              initialize_empty: true
          attribute :max_length, :max_length, collection: true,
                                              initialize_empty: true
          attribute :white_space, :white_space, collection: true,
                                                initialize_empty: true
          attribute :enumeration, :enumeration, collection: true,
                                                initialize_empty: true
          attribute :total_digits, :total_digits, collection: true,
                                                  initialize_empty: true
          attribute :max_exclusive, :max_exclusive, collection: true,
                                                    initialize_empty: true
          attribute :min_exclusive, :min_exclusive, collection: true,
                                                    initialize_empty: true
          attribute :max_inclusive, :max_inclusive, collection: true,
                                                    initialize_empty: true
          attribute :min_inclusive, :min_inclusive, collection: true,
                                                    initialize_empty: true
          attribute :fraction_digits, :fraction_digits, collection: true,
                                                        initialize_empty: true

          xml do
            element "restriction"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :base, to: :base
            map_element :length, to: :length
            map_element :pattern, to: :pattern
            map_element :minLength, to: :min_length
            map_element :maxLength, to: :max_length
            map_element :annotation, to: :annotation
            map_element :whiteSpace, to: :white_space
            map_element :simple_type, to: :simple_type
            map_element :enumeration, to: :enumeration
            map_element :totalDigits, to: :total_digits
            map_element :maxExclusive, to: :max_exclusive
            map_element :minExclusive, to: :min_exclusive
            map_element :maxInclusive, to: :max_inclusive
            map_element :minInclusive, to: :min_inclusive
            map_element :fractionDigits, to: :fraction_digits
          end

          Lutaml::Xml::Schema::Xsd.register_model(self,
                                                  :restriction_simple_type)
        end
      end
    end
  end
end
