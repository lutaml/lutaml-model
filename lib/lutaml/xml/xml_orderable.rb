# frozen_string_literal: true

module Lutaml
  module Xml
    # Mixin for XML element/attribute ordering state.
    #
    # Included by:
    #   - Lutaml::Xml::Serialization::InstanceMethods (Serialize instances)
    #   - Plain model classes via add_format_specific_model_methods
    #
    # Enables Lutaml::Model to check ordering capability with is_a? instead
    # of respond_to?, following proper OOP type-checking.
    module XmlOrderable
      attr_accessor :element_order, :attribute_order, :ordered, :mixed
    end
  end
end
