require_relative "../mapping/mapping"
require_relative "mapping_rule"

module Lutaml
  module Model
    module Xml
      class Mapping < Mapping
        TYPES = {
          attribute: :map_attribute,
          element: :map_element,
          content: :map_content,
          all_content: :map_all,
        }.freeze

        attr_reader :root_element,
                    :namespace_uri,
                    :namespace_prefix,
                    :mixed_content,
                    :ordered,
                    :element_sequence,
                    :mappings_imported,
                    :namespace_class,
                    :element_name,
                    :documentation_text,
                    :type_name_value

        def initialize
          super

          @elements = {}
          @attributes = {}
          @element_sequence = []
          @content_mapping = nil
          @raw_mapping = nil
          @mixed_content = false
          @format = :xml
          @mappings_imported = true
          @finalized = false
          @element_name = nil
          @namespace_class = nil
          @documentation_text = nil
          @type_name_value = nil
        end

        def finalize(mapper_class)
          if !root_element && !no_root?
            root(mapper_class.model.to_s)
          end
          @finalized = true
        end

        def finalized?
          @finalized
        end

        alias mixed_content? mixed_content
        alias ordered? ordered

        # Set the XML element name for this mapping
        #
        # This is the primary method for declaring the element name.
        # Use this for the new clean API.
        #
        # @param name [String] the element name
        # @return [String] the element name
        def element(name)
          @element_name = name
          @root_element = name # Maintain backward compatibility
        end

        # Set the root element name with optional configuration
        #
        # This is kept as an alias to element() for backward compatibility,
        # but also supports the mixed: and ordered: options.
        #
        # @param name [String] the root element name
        # @param mixed [Boolean] whether content is mixed (text + elements)
        # @param ordered [Boolean] whether to preserve element order
        # @return [String] the root element name
        def root(name, mixed: false, ordered: false)
          element(name)
          @mixed_content = mixed
          @ordered = ordered || mixed # mixed content is always ordered
        end

        # Enable mixed content for this element
        #
        # Mixed content means the element can contain both text nodes
        # and child elements interspersed.
        #
        # @return [Boolean] true
        def mixed_content
          @mixed_content = true
          @ordered = true # mixed content implies ordered
        end

        def root?
          !!root_element
        end

        # Mark this model as having no root element (type-only)
        #
        # @deprecated Use absence of element() declaration instead
        def no_root
          warn "[Lutaml::Model] DEPRECATED: no_root is deprecated. " \
               "Simply omit the element declaration for type-only models."
          @no_root = true
          # NOTE: Intentionally NOT clearing @element_name or @root_element here
          # for backward compatibility with Collections during deprecation period
        end

        def no_root?
          !!@no_root
        end

        # Check if this mapping has no element declaration
        #
        # @return [Boolean] true if no element is declared
        def no_element?
          !element_name
        end

        def prefixed_root
          if namespace_uri && namespace_prefix
            "#{namespace_prefix}:#{root_element}"
          else
            root_element
          end
        end

        # Set the XML namespace for this mapping
        #
        # @param uri_or_class [String, Class] namespace URI or XmlNamespace class
        # @param prefix [String, Symbol, nil] optional prefix (for String URI only)
        # @return [void]
        #
        # @example Using XmlNamespace class (preferred)
        #   namespace ContactNamespace
        #
        # @example Using String URI (legacy, still supported)
        #   namespace 'https://example.com/ns', 'ex'
        #
        # @raise [ArgumentError] if invalid arguments provided
        # @raise [Lutaml::Model::NoRootNamespaceError] if called with no_root
        def namespace(uri_or_class, prefix = nil)
          raise Lutaml::Model::NoRootNamespaceError if no_root?

          if uri_or_class.is_a?(Class) && uri_or_class < Lutaml::Model::XmlNamespace
            # XmlNamespace class passed
            @namespace_class = uri_or_class
            @namespace_uri = uri_or_class.uri
            @namespace_prefix = prefix || uri_or_class.prefix_default
          elsif uri_or_class.is_a?(String)
            # Legacy: String URI passed
            validate_namespace_prefix!(prefix)
            @namespace_uri = uri_or_class
            @namespace_prefix = prefix
          else
            raise ArgumentError,
                  "namespace must be a String URI or XmlNamespace class, " \
                  "got #{uri_or_class.class}"
          end
        end

        # Set documentation text for this mapping
        #
        # Used for XSD annotation generation.
        #
        # @param text [String] the documentation text
        # @return [String] the documentation text
        def documentation(text)
          @documentation_text = text
        end

        # Set explicit type name for XSD generation
        #
        # By default, type name is inferred as "ClassNameType".
        # Use this to override.
        #
        # @param name [String, nil] the type name
        # @return [String, nil] the type name
        def type_name(name = nil)
          @type_name_value = name if name
          @type_name_value
        end

        def map_instances(to:, polymorphic: {})
          map_element(to, to: to, polymorphic: polymorphic)
        end

        def map_element(
          name,
          to: nil,
          render_nil: false,
          render_default: false,
          render_empty: false,
          treat_nil: :nil,
          treat_empty: :empty,
          treat_omitted: :nil,
          with: {},
          delegate: nil,
          cdata: false,
          polymorphic: {},
          namespace: (namespace_set = false
                      nil),
          prefix: (prefix_set = false
                   nil),
          transform: {},
          value_map: {},
          form: nil,
          documentation: nil
        )
          validate!(
            name, to, with, render_nil, render_empty, type: TYPES[:element]
          )

          rule = MappingRule.new(
            name,
            to: to,
            render_nil: render_nil,
            render_default: render_default,
            render_empty: render_empty,
            treat_nil: treat_nil,
            treat_empty: treat_empty,
            treat_omitted: treat_omitted,
            with: with,
            delegate: delegate,
            cdata: cdata,
            namespace: namespace,
            default_namespace: namespace_uri,
            prefix: prefix,
            polymorphic: polymorphic,
            namespace_set: namespace_set != false,
            prefix_set: prefix_set != false,
            transform: transform,
            value_map: value_map,
            form: form,
            documentation: documentation,
          )
          @elements[rule.namespaced_name] = rule
        end

        def map_attribute(
          name,
          to: nil,
          render_nil: false,
          render_default: false,
          render_empty: false,
          with: {},
          delegate: nil,
          polymorphic_map: {},
          namespace: (namespace_set = false
                      nil),
          prefix: (prefix_set = false
                   nil),
          transform: {},
          value_map: {},
          as_list: nil,
          delimiter: nil,
          form: nil,
          documentation: nil
        )
          validate!(
            name, to, with, render_nil, render_empty, type: TYPES[:attribute]
          )

          if name == "schemaLocation"
            Logger.warn_auto_handling(
              name: name,
              caller_file: File.basename(caller_locations(1, 1)[0].path),
              caller_line: caller_locations(1, 1)[0].lineno,
            )
          end

          rule = MappingRule.new(
            name,
            to: to,
            render_nil: render_nil,
            render_default: render_default,
            with: with,
            delegate: delegate,
            namespace: namespace,
            prefix: prefix,
            attribute: true,
            polymorphic_map: polymorphic_map,
            default_namespace: namespace_uri,
            namespace_set: namespace_set != false,
            prefix_set: prefix_set != false,
            transform: transform,
            value_map: value_map,
            as_list: as_list,
            delimiter: delimiter,
            form: form,
            documentation: documentation,
          )
          @attributes[rule.namespaced_name] = rule
        end

        def map_content(
          to: nil,
          render_nil: false,
          render_default: false,
          render_empty: false,
          with: {},
          delegate: nil,
          mixed: false,
          cdata: false,
          transform: {},
          value_map: {}
        )
          validate!(
            "content", to, with, render_nil, render_empty, type: TYPES[:content]
          )

          @content_mapping = MappingRule.new(
            nil,
            to: to,
            render_nil: render_nil,
            render_default: render_default,
            render_empty: render_empty,
            with: with,
            delegate: delegate,
            mixed_content: mixed,
            cdata: cdata,
            transform: transform,
            value_map: value_map,
          )
        end

        def map_all(
          to:,
          render_nil: false,
          render_default: false,
          delegate: nil,
          with: {},
          namespace: (namespace_set = false
                      nil),
          prefix: (prefix_set = false
                   nil),
          render_empty: false
        )
          validate!(
            Constants::RAW_MAPPING_KEY,
            to,
            with,
            render_nil,
            render_empty,
            type: TYPES[:all_content],
          )

          rule = MappingRule.new(
            Constants::RAW_MAPPING_KEY,
            to: to,
            render_nil: render_nil,
            render_default: render_default,
            with: with,
            delegate: delegate,
            namespace: namespace,
            prefix: prefix,
            default_namespace: namespace_uri,
            namespace_set: namespace_set != false,
            prefix_set: prefix_set != false,
          )

          @raw_mapping = rule
        end

        alias map_all_content map_all

        def sequence(&block)
          @element_sequence << Sequence.new(self).tap do |s|
            s.instance_eval(&block)
          end
        end

        def import_model_mappings(model)
          return import_mappings_later(model) if model_importable?(model)
          raise Lutaml::Model::ImportModelWithRootError.new(model) if model.root?

          mappings = model.mappings_for(:xml)
          @elements.merge!(mappings.instance_variable_get(:@elements))
          @attributes.merge!(mappings.instance_variable_get(:@attributes))
          (@element_sequence << mappings.element_sequence).flatten!
        end

        def set_mappings_imported(value)
          @mappings_imported = value
        end

        def validate!(key, to, with, render_nil, render_empty, type: nil)
          validate_raw_mappings!(type)
          validate_to_and_with_arguments!(key, to, with)

          if render_nil == :as_empty || render_empty == :as_empty
            raise IncorrectMappingArgumentsError.new(
              ":as_empty is not supported for XML mappings",
            )
          end
        end

        def validate_to_and_with_arguments!(key, to, with)
          if to.nil? && with.empty?
            raise IncorrectMappingArgumentsError.new(
              ":to or :with argument is required for mapping '#{key}'",
            )
          end

          validate_with_options!(key, to, with)
        end

        def validate_with_options!(key, to, with)
          return true if to

          if !with.empty? && (with[:from].nil? || with[:to].nil?)
            raise IncorrectMappingArgumentsError.new(
              ":with argument for mapping '#{key}' requires :to and :from keys",
            )
          end
        end

        def validate_raw_mappings!(type)
          if !@raw_mapping.nil? && type != TYPES[:attribute]
            raise StandardError, "#{type} is not allowed, only #{TYPES[:attribute]} " \
                                 "is allowed with #{TYPES[:all_content]}"
          end

          if !(elements.empty? && content_mapping.nil?) && type == TYPES[:all_content]
            raise StandardError,
                  "#{TYPES[:all_content]} is not allowed with other mappings"
          end
        end

        # Validate namespace prefix parameter
        #
        # Raises ArgumentError if prefix is Hash or Array, which indicates
        # the common mistake of passing options as prefix.
        #
        # @param prefix [Object] the prefix parameter to validate
        # @raise [ArgumentError] if prefix is Hash or Array
        # @return [void]
        def validate_namespace_prefix!(prefix)
          if prefix.is_a?(Hash) || prefix.is_a?(Array)
            raise ArgumentError,
                  "namespace prefix must be a String or Symbol, not #{prefix.class}. " \
                  "Did you mean to use 'root' with mixed: true?"
          end
        end

        def elements
          @elements.values
        end

        def attributes
          @attributes.values
        end

        def content_mapping
          @content_mapping
        end

        def raw_mapping
          @raw_mapping
        end

        def mappings(register_id = nil)
          ensure_mappings_imported!(register_id) if finalized?
          elements + attributes + [content_mapping, raw_mapping].compact
        end

        def ensure_mappings_imported!(register_id = nil)
          return if @mappings_imported

          importable_mappings.each do |model|
            import_model_mappings(
              register(register_id).get_class_without_register(model),
            )
          end

          sequence_importable_mappings.each do |sequence, models|
            models.each do |model|
              sequence.import_model_mappings(
                register(register_id).get_class_without_register(model),
              )
            end
          end

          @mappings_imported = true
        end

        def importable_mappings
          @importable_mappings ||= []
        end

        def sequence_importable_mappings
          @sequence_importable_mappings ||= ::Hash.new { |h, k| h[k] = [] }
        end

        # Find element mapping rule by attribute name
        #
        # @param name [Symbol, String] the attribute name
        # @return [MappingRule, nil] the matching element rule
        def find_element(name)
          elements.detect { |rule| name == rule.to }
        end

        # Find attribute mapping rule by attribute name
        #
        # @param name [Symbol, String] the attribute name
        # @return [MappingRule, nil] the matching attribute rule
        def find_attribute(name)
          attributes.detect { |rule| name == rule.to }
        end

        def find_by_name(name, type: "Text")
          if ["text", "#cdata-section"].include?(name.to_s) && type == "Text"
            content_mapping
          else
            mappings.detect do |rule|
              rule.name == name.to_s || rule.name == name.to_sym
            end
          end
        end

        def find_by_to(to)
          mappings.detect { |rule| rule.to.to_s == to.to_s }
        end

        def find_by_to!(to)
          mapping = find_by_to(to)

          return mapping if !!mapping

          raise raise Lutaml::Model::NoMappingFoundError.new(to.to_s)
        end

        def mapping_attributes_hash
          @attributes
        end

        def mapping_elements_hash
          @elements
        end

        def merge_mapping_attributes(mapping)
          mapping_attributes_hash.merge!(mapping.mapping_attributes_hash)
        end

        def merge_mapping_elements(mapping)
          mapping_elements_hash.merge!(mapping.mapping_elements_hash)
        end

        def merge_elements_sequence(mapping)
          mapping.element_sequence.each do |sequence|
            element_sequence << Lutaml::Model::Sequence.new(self).tap do |instance|
              sequence.attributes.each do |attr|
                instance.attributes << attr.deep_dup
              end
            end
          end
        end

        def deep_dup
          self.class.new.tap do |xml_mapping|
            xml_mapping.root(@root_element.dup, mixed: @mixed_content,
                                                ordered: @ordered) if @root_element
            if @namespace_uri
              xml_mapping.namespace(@namespace_uri.dup,
                                    @namespace_prefix&.dup)
            end

            attributes_to_dup.each do |var_name|
              value = instance_variable_get(var_name)
              xml_mapping.instance_variable_set(var_name, Utils.deep_dup(value))
            end
            xml_mapping.instance_variable_set(:@finalized, true)
          end
        end

        def polymorphic_mapping
          mappings.find(&:polymorphic_mapping?)
        end

        def attributes_to_dup
          @attributes_to_dup ||= %i[
            @content_mapping
            @raw_mapping
            @element_sequence
            @attributes
            @elements
          ]
        end

        def dup_mappings(mappings)
          new_mappings = {}

          mappings.each do |key, mapping_rule|
            new_mappings[key] = mapping_rule.deep_dup
          end

          new_mappings
        end

        private

        def register(register_id = nil)
          register_id ||= Lutaml::Model::Config.default_register
          Lutaml::Model::GlobalRegister.lookup(register_id)
        end

        def model_importable?(model)
          model.is_a?(Symbol) || model.is_a?(String)
        end

        def import_mappings_later(model)
          importable_mappings << model.to_sym
          @mappings_imported = false
        end
      end
    end
  end
end
