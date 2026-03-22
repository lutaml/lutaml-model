module Lutaml
  module Xml
    class Mapping < ::Lutaml::Model::Mapping
      TYPES = {
        attribute: :map_attribute,
        element: :map_element,
        content: :map_content,
        all_content: :map_all,
      }.freeze

      # Class-level XML DSL for reusable mapping classes.
      #
      # When a subclass of Lutaml::Xml::Mapping uses `xml do...end` in its
      # class body, this method creates an instance and evaluates the block.
      #
      # @param block [Proc] DSL block with map_element, namespace_scope, etc.
      # @return [Lutaml::Xml::Mapping] the mapping instance
      #
      # @example
      #   class BaseMapping < Lutaml::Xml::Mapping
      #     xml do
      #       namespace_scope [MyNamespace]
      #       map_element "Foo", to: :foo
      #     end
      #   end
      def self.xml(&block)
        @xml_instance ||= new
        @xml_instance.instance_eval(&block) if block
        @xml_instance
      end

      # Get the shared XML mapping instance for this mapping class.
      # Created lazily via the xml() class method.
      #
      # @return [Lutaml::Xml::Mapping, nil]
      def self.xml_mapping_instance
        @xml_instance
      end

      attr_reader :root_element,
                  :namespace_uri,
                  :namespace_prefix,
                  :mixed_content,
                  :element_sequence,
                  :mappings_imported,
                  :namespace_class,
                  :namespace_param,
                  :element_name,
                  :documentation_text,
                  :type_name_value,
                  :namespace_scope,
                  :namespace_scope_config,
                  :mapper_class

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
        @namespace_scope = []
        @namespace_scope_config = []
        @mapper_class = nil
        @importing_mappings = false
        @attributes_with_methods_defined = Set.new
      end

      def finalize(mapper_class)
        # Store mapper class for later use in deferred imports
        @mapper_class = mapper_class

        # DO NOT auto-generate root element
        # Models should explicitly declare root in their xml block if needed
        # Type-only models (used as nested types) don't need a root element

        # Resolve any deferred mapping imports before finalizing
        ensure_mappings_imported!

        @finalized = true
      end

      def finalized?
        @finalized
      end

      alias mixed_content? mixed_content

      # Return whether this mapping uses ordered content
      # @return [Boolean, nil] true if ordered, nil if not set
      def ordered?
        @ordered
      end

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

      # Enable ordered content for this element
      #
      # Ordered content means element order is preserved during
      # round-trip serialization without validation.
      # This is different from `sequence` which enforces and validates order.
      #
      # Use this when:
      # - Element order matters for your application
      # - You need to preserve input order exactly
      # - You DON'T want to validate/enforce specific order
      #
      # Use `sequence` when you need strict order validation.
      #
      # @return [Boolean] true
      def ordered
        @ordered = true
      end

      def root?
        !!root_element
      end

      # Mark this model as having no root element (type-only)
      #
      # @deprecated Use absence of element() declaration and type_name() instead
      def no_root
        warn "[Lutaml::Model] DEPRECATED: no_root is deprecated. " \
             "Simply omit the element declaration for type-only models. " \
             "Use type_name() to set the XSD type name."
        @no_root = true
      end

      # Check if this mapping has no root element
      #
      # Returns true if:
      # - The deprecated @no_root flag is explicitly set, OR
      # - No element is declared (modern pattern - just omit element() call)
      #
      # @return [Boolean] true if no root element
      def no_root?
        !!@no_root || no_element?
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
      # @param ns_class_or_symbol [Class, Symbol] XmlNamespace class or :blank/:inherit
      # @param _deprecated_prefix [String, nil] DEPRECATED - no longer used
      # @return [void]
      #
      # @example Using XmlNamespace class (REQUIRED)
      #   namespace ContactNamespace
      #
      # @example Using :inherit to inherit parent namespace
      #   namespace :inherit
      #
      # @example Using :blank for explicit no namespace
      #   namespace :blank
      #
      # @raise [ArgumentError] if invalid arguments provided
      # @raise [Lutaml::Model::NoRootNamespaceError] if explicitly marked as no_root
      def namespace(ns_class_or_symbol, _deprecated_prefix = nil)
        # Only raise error for explicitly marked no_root (using deprecated method)
        # Type-only models (no element declared) CAN have namespaces
        raise Lutaml::Model::NoRootNamespaceError if @no_root

        # Warn if prefix parameter is provided
        if _deprecated_prefix
          warn "[DEPRECATED] The prefix parameter on namespace() is deprecated. " \
               "Define prefix_default in your XmlNamespace class instead. " \
               "Prefix '#{_deprecated_prefix}' will be ignored."
        end

        # Handle :blank symbol - explicit blank namespace
        if ns_class_or_symbol == :blank
          @namespace_class = nil
          @namespace_uri = nil
          @namespace_prefix = nil
          @namespace_set = true # Mark as explicitly set
          @namespace_param = :blank # Store original value
          return
        end

        # Handle :inherit symbol
        if ns_class_or_symbol == :inherit
          @namespace_set = true
          @namespace_param = :inherit
          return
        end

        # nil means "not set" - DON'T set @namespace_set
        if ns_class_or_symbol.nil?
          @namespace_class = nil
          @namespace_uri = nil
          @namespace_prefix = nil
          @namespace_set = false # Explicitly NOT set
          @namespace_param = nil
          return
        end

        # Accept both Lutaml::Xml::Namespace and Lutaml::Model::Xml::Namespace for compatibility
        is_namespace_class = ns_class_or_symbol.is_a?(Class) && (
          (defined?(::Lutaml::Xml::Namespace) && ns_class_or_symbol < ::Lutaml::Xml::Namespace) ||
          (defined?(::Lutaml::Model::Xml::Namespace) && ns_class_or_symbol < ::Lutaml::Model::Xml::Namespace)
        )

        if is_namespace_class
          # XmlNamespace class passed - register and use
          @namespace_class = NamespaceClassRegistry.instance.register_named(ns_class_or_symbol)
          @namespace_uri = ns_class_or_symbol.uri
          @namespace_prefix = ns_class_or_symbol.prefix_default
        elsif ns_class_or_symbol.is_a?(String)
          # String URI - NOT SUPPORTED
          raise Lutaml::Xml::Error::InvalidNamespaceError.new(
            expected: "XmlNamespace class",
            got: ns_class_or_symbol,
            message: "String namespace URIs are not supported. " \
                     "Define an XmlNamespace class instead. " \
                     "See docs/_guides/xml-namespaces.adoc for migration guide.",
          )
        else
          raise Lutaml::Xml::Error::InvalidNamespaceError.new(
            expected: "XmlNamespace class, :inherit, or :blank",
            got: ns_class_or_symbol,
          )
        end
      end

      # Set the namespace scope for this mapping
      #
      # Controls which namespaces are declared at the root element level
      # versus being declared locally on each element that uses them.
      #
      # Namespaces listed in namespace_scope will be declared once on the
      # root element. Namespaces not listed will be declared locally on
      # elements where they are used.
      #
      # @param namespaces [Array<Class>, Array<Hash>] array of XmlNamespace classes
      #   or hashes with :namespace and :declare keys
      # @return [Array<Class>] the current namespace scope
      #
      # @example Simple array of namespace classes (all default to :auto)
      #   namespace_scope [VcardNamespace, DctermsNamespace, DcElementsNamespace]
      #
      # @example Per-namespace declaration control
      #   namespace_scope [
      #     { namespace: VcardNamespace, declare: :always },
      #     { namespace: DctermsNamespace, declare: :auto },
      #     XsiNamespace  # Can mix hash and class entries
      #   ]
      def namespace_scope(namespaces = nil)
        if namespaces
          validate_namespace_scope!(namespaces)

          # Convert to normalized format
          @namespace_scope_config = normalize_namespace_scope(namespaces)
          @namespace_scope = @namespace_scope_config.map do |cfg|
            cfg[:namespace]
          end
        end
        @namespace_scope
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

      # Alias for type_name - both methods are equivalent
      #
      # xsd_type and type_name set the XSD complexType/simpleType name
      # for schema generation. Use type_name for clarity (recommended).
      #
      # @param name [String, nil] the type name
      # @return [String, nil] the type name
      alias xsd_type type_name

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
      prefix: (prefix_provided = false
               nil),
      transform: {},
      value_map: {},
      form: nil,
      documentation: nil,
      xsd_type: (xsd_type_provided = false
                 nil)
      )
        validate!(
          name, to, with, render_nil, render_empty, type: TYPES[:element]
        )

        # Warn if prefix parameter is provided
        if prefix_provided != false
          warn "[DEPRECATED] The prefix parameter on map_element is deprecated. " \
               "Define prefix_default in your XmlNamespace class instead. " \
               "Prefix '#{prefix}' will be ignored."
        end

        # Raise error if xsd_type parameter is provided
        if xsd_type_provided != false
          raise Lutaml::Model::IncorrectMappingArgumentsError,
                "xsd_type is not allowed at mapping level. " \
                "XSD type must be declared in Type::Value classes using the xsd_type directive. " \
                "See docs/migration-guides/xsd-type-migration.adoc"
        end

        # Raise error if namespace parameter is a non-nil value at element level
        # This is NOT allowed - namespaces should be declared at model level
        # However, namespace: nil is allowed to explicitly opt out of namespace
        # Note: namespace_set is false when default is used, nil when explicit arg passed
        if namespace_set != false && !namespace.nil?
          raise Lutaml::Model::IncorrectMappingArgumentsError,
                "namespace is not allowed at element mapping level. " \
                "Namespaces must be declared on the MODEL CLASS itself using 'namespace' at the xml block level. " \
                "Each model class should declare its own namespace, not individual elements."
        end

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
          polymorphic: polymorphic,
          namespace_set: namespace_set != false || namespace == :inherit,
          transform: transform,
          value_map: value_map,
          form: form,
          documentation: documentation,
        )
        # Store rules with the same element name in an array to support
        # multiple mapping rules for the same element name with different target types
        # Use eql? to detect and skip exact duplicates (prevents accumulation)
        key = rule.namespaced_name
        existing = @elements[key]

        if existing.nil?
          # New mapping - store directly
          @elements[key] = rule
        elsif existing.is_a?(Array)
          # Array exists - check for duplicate or add
          duplicate_index = existing.find_index { |r| r.eql?(rule) }
          # Only add if not a duplicate
          existing << rule unless duplicate_index
        elsif existing.eql?(rule)
          # Exact duplicate - already stored, no action needed
        else
          # Different mapping (polymorphic) - convert to array
          @elements[key] = [existing, rule]
        end
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
      prefix: (prefix_provided = false
               nil),
      transform: {},
      value_map: {},
      as_list: nil,
      delimiter: nil,
      form: nil,
      documentation: nil,
      xsd_type: (xsd_type_provided = false
                 nil)
      )
        validate!(
          name, to, with, render_nil, render_empty, type: TYPES[:attribute]
        )

        # Warn if prefix parameter is provided
        if prefix_provided != false
          warn "[DEPRECATED] The prefix parameter on map_attribute is deprecated. " \
               "Define prefix_default in your XmlNamespace class instead. " \
               "Prefix '#{prefix}' will be ignored."
        end

        # Raise error if xsd_type parameter is provided
        if xsd_type_provided != false
          raise Lutaml::Model::IncorrectMappingArgumentsError,
                "xsd_type is not allowed at mapping level. " \
                "XSD type must be declared in Type::Value classes using the xsd_type directive. " \
                "See docs/migration-guides/xsd-type-migration.adoc"
        end

        # Raise error if namespace parameter is a non-nil value at attribute level
        # This is NOT allowed - namespaces should be declared at model level
        # However, namespace: nil is allowed to explicitly opt out of namespace
        # Note: namespace_set is false when default is used, nil when explicit arg passed
        if namespace_set != false && !namespace.nil?
          raise Lutaml::Model::IncorrectMappingArgumentsError,
                "namespace is not allowed at attribute mapping level. " \
                "Namespaces should be declared on the MODEL CLASS itself using 'namespace' at the xml block level."
        end

        if name == "schemaLocation"
          ::Lutaml::Model::Logger.warn_auto_handling(
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
          render_empty: render_empty,
          with: with,
          delegate: delegate,
          namespace: namespace,
          attribute: true,
          polymorphic_map: polymorphic_map,
          default_namespace: namespace_uri,
          namespace_set: namespace_set != false,
          transform: transform,
          value_map: value_map,
          as_list: as_list,
          delimiter: delimiter,
          form: form,
          documentation: documentation,
        )
        # Use eql? to detect and skip exact duplicates (prevents accumulation)
        key = rule.namespaced_name
        existing = @attributes[key]

        if existing.nil?
          # New mapping - store directly
          @attributes[key] = rule
        elsif existing.is_a?(Array)
          # Array exists - check for duplicate or add
          duplicate_index = existing.find_index { |r| r.eql?(rule) }
          # Only add if not a duplicate
          existing << rule unless duplicate_index
        elsif existing.eql?(rule)
          # Exact duplicate - already stored, no action needed
        else
          # Different mapping (polymorphic) - convert to array
          @attributes[key] = [existing, rule]
        end
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
      prefix: (prefix_provided = false
               nil),
      render_empty: false
      )
        validate!(
          ::Lutaml::Model::Constants::RAW_MAPPING_KEY,
          to,
          with,
          render_nil,
          render_empty,
          type: TYPES[:all_content],
        )

        # Warn if prefix parameter is provided
        if prefix_provided != false
          warn "[DEPRECATED] The prefix parameter on map_all is deprecated. " \
               "Define prefix_default in your XmlNamespace class instead. " \
               "Prefix '#{prefix}' will be ignored."
        end

        # Raise error if namespace parameter is provided
        if namespace_set != false
          raise Lutaml::Model::IncorrectMappingArgumentsError,
                "namespace is not allowed at map_all level. " \
                "Namespaces must be declared on the MODEL CLASS itself using 'namespace' at the xml block level."
        end

        rule = MappingRule.new(
          ::Lutaml::Model::Constants::RAW_MAPPING_KEY,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
          namespace: namespace,
          default_namespace: namespace_uri,
          namespace_set: namespace_set != false,
        )

        @raw_mapping = rule
      end

      alias map_all_content map_all

      def sequence(&block)
        @element_sequence << ::Lutaml::Model::Sequence.new(self).tap do |s|
          s.instance_eval(&block)
        end
      end

      def import_model_mappings(model, register_id = nil)
        register_id ||= Lutaml::Model::Config.default_register
        reg_id = register_id
        return import_mappings_later(model) if model_importable?(model)
        raise Lutaml::Model::ImportModelWithRootError.new(model) if model.root?(reg_id)

        # CRITICAL: Access raw mapping structure directly without triggering import resolution
        # Calling model.mappings_for() can trigger ensure_imports! on that model
        # which creates circular chains: A imports B, B's mappings_for imports C, C imports A
        # Architecture: Access data structure directly, don't call methods that trigger resolutions
        mappings = model.instance_variable_get(:@mappings)&.dig(:xml)
        return unless mappings # Skip if no XML mappings defined

        # ATOMIC IMPORT: Both object model (attributes) AND serialization mappings
        # This mimics XSD complexType composition where importing a type means
        # getting both its structure (attributes) and serialization rules (mappings)

        # 1. Import object model (attributes with accessors)
        #    This defines the data structure of the model
        # CRITICAL: Access attributes directly to avoid triggering ensure_imports!
        imported_attributes = ::Lutaml::Model::Utils.deep_dup(model.instance_variable_get(:@attributes)&.values || [])
        if @mapper_class
          imported_attributes.each do |attr|
            # CRITICAL: Check LOCAL set to avoid calling @mapper_class.attributes()
            # which can trigger ensure_imports! and create circular calls
            unless @attributes_with_methods_defined.include?(attr.name)
              # Define accessor methods on the model class
              @mapper_class.define_attribute_methods(attr, reg_id)
              @attributes_with_methods_defined.add(attr.name)
            end
          end
          # Merge attributes data - use direct access to avoid triggering imports
          attrs_hash = imported_attributes.to_h { |attr| [attr.name, attr] }
          existing_attrs = @mapper_class.instance_variable_get(:@attributes) || {}
          existing_attrs.merge!(attrs_hash)
          @mapper_class.instance_variable_set(:@attributes, existing_attrs)
        end

        # 2. Import serialization mappings (XML element/attribute names → model attributes)
        #    This defines how the data structure maps to/from XML
        # CRITICAL: Deep-copy mapping rules to prevent shared state
        # When multiple classes import the same model, each must have independent MappingRule instances
        # Otherwise, any state mutation during serialization affects ALL importing classes
        @elements.merge!(dup_mappings(mappings.instance_variable_get(:@elements)))
        @attributes.merge!(dup_mappings(mappings.instance_variable_get(:@attributes)))
        # CRITICAL: Deep-copy sequences to prevent shared state
        # Each importing class must have its own Sequence objects
        imported_sequences = mappings.element_sequence.map do |seq|
          seq.deep_dup(self)
        end
        (@element_sequence << imported_sequences).flatten!
      end

      def set_mappings_imported(value)
        @mappings_imported = value
      end

      def validate!(key, to, with, render_nil, render_empty, type: nil)
        validate_raw_mappings!(type)
        validate_to_and_with_arguments!(key, to, with)

        if render_nil == :as_empty || render_empty == :as_empty
          raise ::Lutaml::Model::IncorrectMappingArgumentsError.new(
            ":as_empty is not supported for XML mappings. " \
            "Use :as_blank instead to create blank XML elements.",
          )
        end
      end

      def validate_to_and_with_arguments!(key, to, with)
        if to.nil? && with.empty?
          raise ::Lutaml::Model::IncorrectMappingArgumentsError.new(
            ":to or :with argument is required for mapping '#{key}'",
          )
        end

        validate_with_options!(key, to, with)
      end

      def validate_with_options!(key, to, with)
        return true if to

        if !with.empty? && (with[:from].nil? || with[:to].nil?)
          raise ::Lutaml::Model::IncorrectMappingArgumentsError.new(
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

      # Validate namespace_scope parameter
      #
      # Ensures all items are XmlNamespace classes or valid Hash entries
      #
      # @param namespaces [Array] the namespaces to validate
      # @raise [ArgumentError] if invalid namespace classes provided
      # @return [void]
      def validate_namespace_scope!(namespaces)
        unless namespaces.is_a?(Array)
          raise ArgumentError,
                "namespace_scope must be an Array of XmlNamespace classes, " \
                "got #{namespaces.class}"
        end

        namespaces.each do |ns|
          if ns.is_a?(Class)
            unless ns < Lutaml::Xml::Namespace
              raise ArgumentError,
                    "namespace_scope must contain only XmlNamespace classes, " \
                    "got #{ns}"
            end
          elsif ns.is_a?(::Hash)
            ns_class = ns[:namespace]
            unless ns_class.is_a?(Class) && ns_class < Lutaml::Xml::Namespace
              raise ArgumentError,
                    "namespace_scope Hash entry must have :namespace key " \
                    "with XmlNamespace class, got #{ns_class.class}"
            end

            # Validate :declare option if present
            if ns.key?(:declare)
              declare_value = ns[:declare]
              valid_modes = %i[auto always never]
              unless valid_modes.include?(declare_value)
                raise ArgumentError,
                      "namespace_scope Hash entry :declare must be one of " \
                      "#{valid_modes.inspect}, got #{declare_value.inspect}"
              end
            end
          else
            raise ArgumentError,
                  "namespace_scope must contain only XmlNamespace classes or Hashes, " \
                  "got #{ns.class}"
          end
        end
      end

      def elements
        # Flatten arrays that are created when multiple rules have the same element name
        @elements.values.flat_map { |v| v.is_a?(Array) ? v : [v] }
      end

      def attributes
        # Flatten arrays that are created when multiple rules have the same attribute name
        @attributes.values.flat_map { |v| v.is_a?(Array) ? v : [v] }
      end

      def content_mapping
        @content_mapping
      end

      def raw_mapping
        @raw_mapping
      end

      def mappings(_register_id = nil)
        # REMOVED LAZY LOADING - imports resolved at class finalization
        elements + attributes + [content_mapping, raw_mapping].compact
      end

      def importable_mappings
        @importable_mappings ||= []
      end

      def ensure_mappings_imported!(register_id = nil)
        # CRITICAL: Return immediately if already imported to prevent redundant processing
        # This prevents the exponential explosion of recursive ensure_imports! calls
        # in complex schemas with hundreds of interdependent classes
        return if @mappings_imported

        # CRITICAL: Prevent re-entrant calls during import processing
        # This prevents infinite loops when importing models that themselves have imports
        # Architecture: Import resolution should be atomic and non-recursive
        return if @importing_mappings

        # Check if there's any work to do - either regular imports OR sequence imports
        return if importable_mappings.empty? && sequence_importable_mappings.empty?

        # Mark as currently importing to prevent re-entrance
        @importing_mappings = true

        register_id ||= Lutaml::Model::Config.default_register

        # Track if all imports were successfully resolved
        all_resolved = true

        # Process each deferred mapping import
        importable_mappings.dup.each do |model_sym|
          begin
            model_class = Lutaml::Model::GlobalContext.resolve_type(model_sym,
                                                                    register_id)
          rescue Lutaml::Model::UnknownTypeError
            # Model not registered yet - skip for now, will retry later
            all_resolved = false
            next
          end

          next if model_class.nil? # Skip if not registered yet

          # Recursively ensure the imported model's imports are resolved
          if model_class.is_a?(Class) && model_class.include?(Lutaml::Model::Serialize)
            model_class.ensure_imports!(register_id)
          end

          # Now import the mappings
          import_model_mappings(model_class, register_id)
        end

        # Clear regular imports queue if all resolved
        if all_resolved
          importable_mappings.clear
        end

        # CRITICAL FIX: Process sequence importable mappings
        # Sequence blocks can have their own deferred imports via import_model_mappings
        # These need to be resolved separately because they add attributes to sequences
        unless sequence_importable_mappings.empty?
          sequence_importable_mappings.each do |sequence, model_syms|
            model_syms.dup.each do |model_sym|
              begin
                model_class = Lutaml::Model::GlobalContext.resolve_type(
                  model_sym, register_id
                )
              rescue Lutaml::Model::UnknownTypeError
                # Model not registered yet - skip for now
                all_resolved = false
                next
              end

              next if model_class.nil?

              # Recursively ensure the imported model's imports are resolved
              if model_class.is_a?(Class) && model_class.include?(Lutaml::Model::Serialize)
                model_class.ensure_imports!(register_id)
              end

              # Now import into the sequence
              # This will call Sequence#import_model_mappings which adds to sequence.attributes
              # and also calls @model.import_model_mappings to add to main mapping
              sequence.import_model_mappings(model_class, register_id)

              # Remove from queue after successful import
              model_syms.delete(model_sym)
            end
          end

          # Clean up empty sequence entries
          sequence_importable_mappings.reject! { |_, models| models.empty? }
        end

        # Mark as fully imported only if both queues are empty
        @mappings_imported = all_resolved && importable_mappings.empty? && sequence_importable_mappings.empty?
      ensure
        # CRITICAL: Always reset the importing flag to prevent deadlock
        # Even if an exception occurs, we must allow future import attempts
        @importing_mappings = false
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

      def find_by_name(name, type: "Text", node_type: nil, namespace_uri: nil)
        # If node_type is provided, use it for type detection (preferred)
        if node_type && %i[text cdata].include?(node_type)
          content_mapping
        # Backward compatibility: still check name for old code that doesn't pass node_type
        elsif ["text", "#cdata-section"].include?(name.to_s) && type == "Text"
          content_mapping
        else
          candidates = mappings.select do |rule|
            rule.name == name.to_s || rule.name == name.to_sym
          end
          return candidates.first if namespace_uri.nil? || candidates.one?

          candidates.find { |r| r.namespace_class&.uri == namespace_uri } || candidates.first
        end
      end

      def find_by_to(to)
        mappings.detect { |rule| rule.to.to_s == to.to_s }
      end

      def find_by_to!(to)
        mapping = find_by_to(to)

        return mapping if !!mapping

        raise Lutaml::Model::NoMappingFoundError.new(to.to_s)
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
          if @root_element
            xml_mapping.root(@root_element.dup, mixed: @mixed_content,
                                                ordered: @ordered)
          end
          if @namespace_class
            xml_mapping.namespace(@namespace_class)
          elsif @namespace_param == :inherit
            xml_mapping.namespace(:inherit)
          elsif @namespace_param == :blank
            xml_mapping.namespace(:blank)
          end

          attributes_to_dup.each do |var_name|
            value = instance_variable_get(var_name)
            xml_mapping.instance_variable_set(var_name, ::Lutaml::Model::Utils.deep_dup(value))
          end
          xml_mapping.instance_variable_set(:@finalized, true)
          # CRITICAL: Do NOT copy @mapper_class to the duplicate
          # The duplicate may be used in a different class context
          # and should not carry over the original's mapper_class reference
          xml_mapping.instance_variable_set(:@mapper_class, nil)
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

      # Add a complex listener for an XML element with a custom handler block.
      #
      # Unlike map_element which creates a simple listener (framework handles
      # deserialization), on_element allows custom deserialization logic.
      #
      # Multiple listeners for the same element are allowed — all matching
      # listeners are invoked during parsing.
      #
      # @param name [String] XML element name
      # @param id [Symbol, String, nil] Unique identifier for override/omit.
      #   If omitted, listener cannot be targeted by omit_listener.
      # @param block [Proc] Custom handler receiving (element, context)
      # @return [void]
      #
      # @example Custom deserialization
      #   class MyMapping < Lutaml::Xml::Mapping
      #     on_element "CustomElement", id: :custom_parse do |element, context|
      #       context[:custom] = CustomParser.parse(element)
      #     end
      #   end
      #
      # @example Multiple listeners for same element
      #   class MyMapping < Lutaml::Xml::Mapping
      #     on_element "Documentation", id: :parse_docs do |element, context|
      #       context[:documentation] = Documentation.from_xml(element)
      #     end
      #
      #     on_element "Documentation", id: :log_docs do |element, context|
      #       logger.info("Parsing docs: #{element.text}")
      #     end
      #   end
      def on_element(name, id: nil, &block)
        add_listener(Lutaml::Xml::Listener.new(
                       target: name,
                       id: id,
                       handler: block,
                     ))
      end

      # Add a complex listener for an XML attribute with a custom handler block.
      #
      # @param name [String] XML attribute name
      # @param id [Symbol, String, nil] Unique identifier for override/omit.
      # @param block [Proc] Custom handler receiving (element, context)
      # @return [void]
      #
      # @example
      #   class MyMapping < Lutaml::Xml::Mapping
      #     on_attribute "xmlAttr", id: :parse_attr do |element, context|
      #       context[:custom] = element["xmlAttr"]
      #     end
      #   end
      def on_attribute(name, id: nil, &block)
        add_listener(Lutaml::Xml::Listener.new(
                       target: name,
                       id: id,
                       handler: block,
                     ))
      end

      # Remove ALL listeners for a given XML element name.
      #
      # @param name [String] XML element name
      # @return [void]
      #
      # @example Remove all listeners for "UnusedElement"
      #   class MyMapping < ParentMapping
      #     omit_element "UnusedElement"
      #   end

      # Remove a specific listener by XML element name and ID.
      #
      # @param name [String] XML element name
      # @param id [Symbol, String] The listener ID to remove
      # @return [void]
      #
      # @example Remove parent's :validate_tags listener
      #   class MyMapping < ParentMapping
      #     omit_listener "TaggedValue", id: :validate_tags
      #   end

      private

      # Normalize namespace_scope input to unified format
      #
      # Converts various input formats into a normalized array of hashes
      # with :namespace and :declare keys.
      #
      # @param namespaces [Array] array of namespace classes or hashes
      # @return [Array<Hash>] normalized config array
      def normalize_namespace_scope(namespaces)
        namespaces.map do |ns_entry|
          if ns_entry.is_a?(::Hash) # Use ::Hash explicitly
            # Hash format already has namespace and optional declare
            # Don't double-nest!
            {
              namespace: ns_entry[:namespace],
              declare: ns_entry[:declare] || :auto, # Default to :auto
            }
          else
            # Simple namespace class - wrap it
            {
              namespace: ns_entry,
              declare: :auto,
            }
          end
        end
      end
    end
  end
end
