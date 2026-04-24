# frozen_string_literal: true

module Lutaml
  module Xml
    module Serialization
      # XML-specific instance methods for Serialize.
      #
      # Prepended into Lutaml::Model::Serialize when XML is loaded.
      # Provides XML-specific instance-level behavior:
      # - XML instance attributes (element_order, schema_location, encoding, doctype, ordered, mixed)
      # - xml_declaration_plan writer / import_declaration_plan method
      # - XML-specific format options preparation
      # - XML root mapping validation
      module InstanceMethods
        # XML declaration plan for namespace preservation during round-trip.
        # Writer is used by :eager mode during parsing. Reader delegates to
        # import_declaration_plan which handles lazy building.
        attr_writer :import_declaration_plan
        attr_accessor :element_order, :schema_location, :encoding, :doctype

        # Store pre-collected namespace data for lazy plan building.
        # This is a plain Hash (no adapter objects) collected during from_xml.
        attr_accessor :pending_namespace_data

        # XML namespace metadata for doubly-defined and alias support.
        # These carry information from deserialization to serialization.
        # Accessor methods use the @__ prefixed ivars for backward compatibility.
        def xml_namespace_prefix
          @__xml_namespace_prefix
        end

        def xml_namespace_prefix=(value)
          @__xml_namespace_prefix = value
        end

        def xml_ns_prefixes
          @__xml_ns_prefixes
        end

        def xml_ns_prefixes=(value)
          @__xml_ns_prefixes = value
        end

        def original_namespace_uri
          @__xml_original_namespace_uri
        end

        def original_namespace_uri=(value)
          @__xml_original_namespace_uri = value
        end

        def xml_declaration
          @xml_declaration
        end

        def xml_declaration=(value)
          @xml_declaration = value
        end

        def raw_schema_location
          @raw_schema_location
        end

        def raw_schema_location=(value)
          @raw_schema_location = value
        end

        # Build or return the cached declaration plan.
        #
        # When import_declaration_plan: :lazy (default), builds the plan from
        # pre-collected namespace data on first call. No-op when no pending
        # data exists (:eager already set, :skip, or programmatic creation).
        #
        # @return [DeclarationPlan, nil] The plan or nil
        def import_declaration_plan
          @import_declaration_plan ||= build_pending_declaration_plan
        end
        attr_writer :ordered, :mixed

        def ordered?
          klass = self.class
          if klass.is_a?(Class) && klass.include?(Lutaml::Model::Serialize)
            klass.mappings_for(:xml, lutaml_register)&.ordered? || false
          else
            !!@ordered
          end
        end

        def mixed?
          klass = self.class
          if klass.is_a?(Class) && klass.include?(Lutaml::Model::Serialize)
            klass.mappings_for(:xml, lutaml_register)&.mixed_content? || false
          else
            !!@mixed
          end
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
              yield(text) if text
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
          xml_internals = %i[@import_declaration_plan @xml_input_namespaces
                             @pending_namespace_data @__xml_namespace_prefix
                             @__xml_ns_prefixes @__xml_original_namespace_uri
                             @xml_declaration @raw_schema_location]
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

          # Pass stored DeclarationPlan for format preservation.
          if import_declaration_plan
            options[:stored_xml_declaration_plan] = import_declaration_plan
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

        # Build declaration plan from pre-collected namespace data (lazy mode).
        # Called by xml_declaration_plan getter on first access.
        # @return [DeclarationPlan, nil]
        def build_pending_declaration_plan
          ns = @pending_namespace_data
          return nil unless ns

          @pending_namespace_data = nil
          xml_mapping = self.class.mappings_for(:xml)
          Lutaml::Xml::DeclarationPlan.from_input_with_locations(ns,
                                                                 xml_mapping)
        end

        def set_ordering(attrs)
          return unless attrs.respond_to?(:item_order)

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
