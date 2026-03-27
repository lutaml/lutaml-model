# frozen_string_literal: true

module Lutaml
  module Xml
    module Serialization
      # XML-specific instance methods for Serialize.
      #
      # Included into Lutaml::Model::Serialize when XML is loaded.
      # Provides XML-specific instance-level behavior:
      # - xml_declaration_plan accessor
      # - XML-specific format options preparation
      # - XML root mapping validation
      module InstanceMethods
        # XML declaration plan for namespace preservation during round-trip
        attr_accessor :xml_declaration_plan

        # Extend INTERNAL_ATTRIBUTES with XML-specific ones
        def pretty_print_instance_variables
          xml_internals = %i[@xml_declaration_plan @xml_input_namespaces]
          super - xml_internals
        end

        # XML-specific root mapping validation
        #
        # @param format [Symbol] The format
        # @param options [Hash] Options hash
        def validate_root_mapping!(format, options)
          return super unless format == :xml
          return if options[:collection] || self.class.root?(lutaml_register)

          raise Lutaml::Model::NoRootMappingError.new(self.class)
        end

        # XML-specific instance options preparation
        #
        # @param format [Symbol] The format
        # @param options [Hash] Options hash (modified in place)
        def prepare_instance_format_options(format, options)
          return super unless format == :xml

          # Handle prefix option (converts to use_prefix for transformation phase)
          if options.key?(:prefix)
            prefix_option = options[:prefix]
            case prefix_option
            when true
              options[:use_prefix] = true
            when String
              options[:use_prefix] = prefix_option
            when false
              options[:use_prefix] = false
            end
            options.delete(:prefix)
          end

          options[:doctype] = doctype if doctype

          # Pass XML declaration info for XML Declaration Preservation
          if instance_variable_defined?(:@xml_declaration) && @xml_declaration
            options[:xml_declaration] = @xml_declaration
          end

          # Pass input namespaces for Namespace Preservation
          if instance_variable_defined?(:@xml_input_namespaces) && @xml_input_namespaces&.any?
            options[:input_namespaces] = @xml_input_namespaces
          end

          # Pass stored DeclarationPlan for format preservation
          if xml_declaration_plan
            options[:stored_xml_declaration_plan] = xml_declaration_plan
          end
        end
      end
    end
  end
end
