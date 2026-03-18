# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class RestrictionSimpleContent < Base
          attribute :id, :string
          attribute :base, :string
          attribute :annotation, :annotation
          attribute :simple_type, :simple_type
          attribute :any_attribute, :any_attribute
          attribute :length, :length, collection: true, initialize_empty: true
          attribute :pattern, :pattern, collection: true, initialize_empty: true
          attribute :attribute, :attribute, collection: true,
                                            initialize_empty: true
          attribute :max_length, :max_length, collection: true,
                                              initialize_empty: true
          attribute :min_length, :min_length, collection: true,
                                              initialize_empty: true
          attribute :white_space, :white_space, collection: true,
                                                initialize_empty: true
          attribute :enumeration, :enumeration, collection: true,
                                                initialize_empty: true
          attribute :total_digits, :total_digits, collection: true,
                                                  initialize_empty: true
          attribute :min_exclusive, :min_exclusive, collection: true,
                                                    initialize_empty: true
          attribute :min_inclusive, :min_inclusive, collection: true,
                                                    initialize_empty: true
          attribute :max_exclusive, :max_exclusive, collection: true,
                                                    initialize_empty: true
          attribute :max_inclusive, :max_inclusive, collection: true,
                                                    initialize_empty: true
          attribute :attribute_group, :attribute_group, collection: true,
                                                        initialize_empty: true
          attribute :fraction_digits, :fraction_digits, collection: true,
                                                        initialize_empty: true

          xml do
            element "restriction"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :base, to: :base
            map_element :fractionDigits, to: :fraction_digits
            map_element :attributeGroup, to: :attribute_group
            map_element :minInclusive, to: :min_inclusive
            map_element :maxInclusive, to: :max_inclusive
            map_element :anyAttribute, to: :any_attribute
            map_element :minExclusive, to: :min_exclusive
            map_element :maxExclusive, to: :max_exclusive
            map_element :totalDigits, to: :total_digits
            map_element :enumeration, to: :enumeration
            map_element :simpleType, to: :simple_type
            map_element :whiteSpace, to: :white_space
            map_element :annotation, to: :annotation
            map_element :maxLength, to: :max_length
            map_element :minLength, to: :min_length
            map_element :attribute, to: :attribute
            map_element :pattern, to: :pattern
            map_element :length, to: :length
          end

          Lutaml::Xml::Schema::Xsd.register_model(self,
                                                  :restriction_simple_content)
        end
      end
    end
  end
end
