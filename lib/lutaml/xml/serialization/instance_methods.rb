# frozen_string_literal: true

module Lutaml
  module Xml
    module Serialization
      # XML-specific instance methods for Serialize.
      #
      # Prepended into Lutaml::Model::Serialize when XML is loaded.
      # Provides XML-specific instance-level behavior:
      # - XML instance attributes (element_order, schema_location, encoding, doctype, ordered, mixed)
      # - xml_declaration_plan accessor
      # - XML-specific format options preparation
      # - XML root mapping validation
      module InstanceMethods
        # XML declaration plan for namespace preservation during round-trip
        attr_accessor :xml_declaration_plan, :element_order, :schema_location,
                      :encoding, :doctype
        attr_writer :ordered, :mixed

        def ordered?
          !!@ordered
        end

        def mixed?
          !!@mixed
        end

        # Iterate over content in document order.
        #
        # Yields String (text nodes) and Lutaml::Model::Serializable (inline elements).
        # Works for both:
        #   - Mixed content: text + elements interleaved
        #   - Ordered content: elements only, but in specific sequence
        #
        # Returns self when called with a block, Enumerator when called without.
        #
        # @example
        #   para.each_mixed_content { |item| puts item.inspect }
        #   # For mixed content => "Hello ", #<Emphasis>, "!"
        #   # For ordered only => #<Item "first">, #<Item "second">
        #
        # @return [self, Enumerator] self if block given, Enumerator otherwise
        def each_mixed_content
          return to_enum(:each_mixed_content) unless block_given?
          # Only iterate for mixed or ordered content
          return unless element_order && (mixed? || ordered?)

          # Get the XML mapping for this class
          xml_mapping = self.class.mappings_for(:xml, lutaml_register)
          return unless xml_mapping

          # Build lookup: element name -> attribute name
          # @elements maps namespaced names to MappingRule or Array<MappingRule>
          # Note: rule.name is a Symbol but el.name from element_order is a String
          # We store both to handle the mismatch
          element_to_attr = {}
          xml_mapping.mapping_elements_hash.each_value do |rule_or_array|
            Array(rule_or_array).each do |rule|
              element_to_attr[rule.name] = rule.to
              if rule.name.is_a?(Symbol)
                element_to_attr[rule.name.to_s] =
                  rule.to
              end
            end
          end

          # Track current index for each collection attribute
          # Using ::Hash to avoid conflict with Lutaml::Model::Hash
          collection_indices = ::Hash.new(0)

          element_order.each do |el|
            if el.text?
              # Text node - yield the text content (skip whitespace-only)
              text = el.text_content
              yield(text) if text && !text.strip.empty?
            elsif el.element?
              # Element node - look up mapped collection and get next item
              attr_name = element_to_attr[el.name]
              next unless attr_name

              collection = send(attr_name)
              next unless collection.is_a?(Array)

              index = collection_indices[attr_name]
              collection_indices[attr_name] += 1

              obj = collection[index]
              yield(obj) if obj
            end
          end

          self
        end

        # Override initialize to extract XML-specific attrs
        def initialize(attrs = {}, options = {})
          super
          set_ordering(attrs)
          set_schema_location(attrs)
          set_doctype(attrs)
        end

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
            when false, :default, nil
              options[:use_prefix] = false
            end
            options.delete(:prefix)
          end

          options[:parse_encoding] = encoding if encoding
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

        # XML-specific element sequences for validation
        #
        # @param register [Symbol, nil] The register context
        # @return [Array, nil] Element sequences from XML mapping
        def format_element_sequences(register)
          self.class.mappings_for(:xml, register)&.element_sequence
        end

        private

        def set_ordering(attrs)
          return unless attrs.respond_to?(:ordered?)

          @ordered = attrs.ordered?
          @element_order = attrs.item_order
        end

        def set_schema_location(attrs)
          return unless attrs.is_a?(Hash) && attrs.key?(:schema_location)

          self.schema_location = attrs[:schema_location]
        end

        def set_doctype(attrs)
          return unless attrs.is_a?(Hash) && attrs.key?(:doctype)

          self.doctype = attrs[:doctype]
        end
      end
    end
  end
end
