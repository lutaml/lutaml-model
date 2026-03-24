# frozen_string_literal: true

module Lutaml
  module Xml
    # Represents the complete namespace declaration plan for an XML element
    #
    # DeclarationPlan uses a TREE STRUCTURE that is isomorphic to XmlDataModel,
    # enabling index-based parallel traversal for W3C-compliant attribute prefix handling.
    #
    # The tree consists of ElementNode objects (containing AttributeNode arrays),
    # structured identically to the XmlDataModel tree to enable position-based matching.
    #
    # @example Creating a tree-mode declaration plan
    #   root_node = DeclarationPlan::ElementNode.new(...)
    #   plan = DeclarationPlan.new(root_node: root_node, global_prefix_registry: {...})
    #
    class DeclarationPlan
      # Autoload inner classes
      autoload :ElementNode, "#{__dir__}/declaration_plan/element_node"
      autoload :AttributeNode, "#{__dir__}/declaration_plan/attribute_node"

      # @return [ElementNode] Root of the element tree containing all decisions
      attr_reader :root_node

      # @return [Hash<String, String>] Global prefix registry (URI => prefix)
      attr_reader :global_prefix_registry

      # @return [Hash<String, Symbol>] Input format tracking (URI => :default or :prefix)
      attr_reader :input_formats

      # @return [Hash<String, Symbol>] Per-(prefix, URI) format tracking for doubly-defined namespaces
      # Key: "#{prefix}:#{uri}" for prefixed, ":#{uri}" for default
      # Value: :default or :prefix
      attr_reader :input_prefix_formats

      # @return [Hash<String, Class>] Namespace classes by URI (for namespace lookup)
      attr_reader :namespace_classes

      # @return [Hash] Children plans (for collection items)
      attr_reader :children_plans

      # @return [Hash<String, String>] Original alias URI mapping (canonical URI => original alias URI)
      # Used for round-trip fidelity when namespace has uri_aliases.
      attr_reader :original_namespace_uris

      # @return [Hash<String, Hash>] Namespace declarations by element path
      # Format: { "elementName" => { nil => "uri" } or { "prefix" => "uri" } }
      # Used for preserving original namespace URIs during serialization.
      attr_reader :namespace_locations

      # Initialize a declaration plan with tree structure
      #
      # @param root_node [ElementNode] Root element node
      # @param global_prefix_registry [Hash<String, String>] Global prefix registry
      # @param input_formats [Hash<String, Symbol>] Input format tracking (URI => format)
      # @param namespace_classes [Hash<String, Class>] Namespace classes by URI
      # @param children_plans [Hash] Children plans for collections
      # @param original_namespace_uris [Hash<String, String>] Original alias URI mapping
      def initialize(root_node:, global_prefix_registry: {},
                     input_formats: {}, namespace_classes: {}, children_plans: {},
                     input_prefix_formats: {}, original_namespace_uris: {})
        @root_node = root_node
        @global_prefix_registry = global_prefix_registry
        @input_formats = input_formats
        @namespace_classes = namespace_classes
        @children_plans = children_plans
        @input_prefix_formats = input_prefix_formats
        @original_namespace_uris = original_namespace_uris

        # Performance: Cached lookups
        @namespaces_cache = nil
        @uri_to_info_cache = nil
      end

      # Backward-compatible Hash-like access for older adapters
      #
      # @param key [Symbol] Key to access (:namespaces, :children_plans, :type_namespaces)
      # @return [Hash, nil] The requested data as a Hash, or nil for unknown keys
      def [](key)
        case key
        when :namespaces
          # Convert namespaces to the old Hash format expected by REXML adapter
          ns_hash = {}
          return nil unless @namespace_classes

          @namespace_classes.each do |uri, ns_class|
            key_str = ns_class.to_key

            # Determine format and build ns_config hash
            format = @input_formats[uri] || (
              if @root_node.hoisted_declarations.value?(uri)
                hoisted_key = @root_node.hoisted_declarations.key(uri)
                hoisted_key.nil? ? :default : :prefix
              else
                ns_class.prefix_default ? :prefix : :default
              end
            )

            prefix_override = nil
            if format == :prefix
              hoisted_key = @root_node.hoisted_declarations.key(uri)
              prefix_override = hoisted_key if hoisted_key
            end

            # Build xmlns_declaration string
            xmlns_decl = if format == :prefix
                           "xmlns:#{prefix_override || ns_class.prefix_default}=\"#{uri}\""
                         else
                           "xmlns=\"#{uri}\""
                         end

            ns_hash[key_str] = {
              ns_object: ns_class,
              format: format,
              declared_at: :here,
              xmlns_declaration: xmlns_decl,
              prefix_override: prefix_override,
            }
          end
          ns_hash
        when :children_plans
          @children_plans
        when :type_namespaces
          # type_namespaces is no longer used in the same way, return empty hash
          {}
        end
      end

      # Create an empty plan (for compatibility)
      #
      # @return [DeclarationPlan] Empty plan instance
      def self.empty
        empty_node = ElementNode.new(
          qualified_name: "",
          use_prefix: nil,
          hoisted_declarations: {},
        )
        new(root_node: empty_node, global_prefix_registry: {})
      end

      # Create DeclarationPlan from parsed XML input namespaces
      # Used during deserialization to capture input format for round-trip preservation
      #
      # @param input_namespaces [Hash] Namespace declarations from parsed XML
      # @param mapping [Xml::Mapping] XML mapping
      # @return [DeclarationPlan] Plan capturing input format
      def self.from_input(input_namespaces, mapping)
        # Create minimal tree with just root node capturing input xmlns
        hoisted = {}

        # Track input formats
        input_formats = {}
        input_prefix_formats = {} # NEW: per-(prefix, URI) format

        input_namespaces.each_value do |ns_config|
          prefix = ns_config[:prefix]
          uri = ns_config[:uri]
          format = ns_config[:format] || (prefix ? :prefix : :default)

          # CRITICAL: Hash key based on FORMAT
          # nil = default namespace (xmlns="...")
          # "prefix" = prefixed namespace (xmlns:prefix="...")
          xmlns_key = if format == :default
                        nil
                      else
                        prefix
                      end
          hoisted[xmlns_key] = uri

          # Track format used in input for this URI
          input_formats[uri] = format

          # NEW: Build per-prefix-URI format
          key = prefix ? "#{prefix}:#{uri}" : ":#{uri}"
          input_prefix_formats[key] = format
        end

        # Build global prefix registry (only for prefixed namespaces)
        registry = {}
        input_namespaces.each_value do |ns_config|
          if ns_config[:format] == :prefix && ns_config[:prefix]
            registry[ns_config[:uri]] = ns_config[:prefix]
          end
        end

        root_node = ElementNode.new(
          qualified_name: mapping.root_element || "",
          use_prefix: nil, # Will be determined from input_formats
          hoisted_declarations: hoisted,
        )

        new(root_node: root_node, global_prefix_registry: registry,
            input_formats: input_formats, input_prefix_formats: input_prefix_formats)
      end

      # Create DeclarationPlan from parsed XML input namespaces WITH location tracking
      #
      # This method preserves WHERE each namespace was declared in the original XML,
      # enabling proper round-trip fidelity for namespace declarations.
      #
      # @param namespaces_with_locations [Hash] Location-aware namespace info
      #   Format: { path_array => namespace_hash }
      #   Where path_array is [] for root, ["child"] for child, etc.
      #   And namespace_hash is { prefix_key => { uri:, format:, prefix: } }
      # @param mapping [Xml::Mapping] XML mapping
      # @return [DeclarationPlan] Plan capturing input format AND location
      def self.from_input_with_locations(namespaces_with_locations, mapping)
        # Build hoisted declarations for root (empty path)
        root_namespaces = namespaces_with_locations[[]] || {}

        # Track input formats for ALL namespaces (for format preservation)
        input_formats = {}
        input_prefix_formats = {} # NEW: per-(prefix, URI) format
        root_hoisted = {}

        # Process root namespaces
        root_namespaces.each_value do |ns_config|
          prefix = ns_config[:prefix]
          uri = ns_config[:uri]
          format = ns_config[:format] || (prefix ? :prefix : :default)

          xmlns_key = format == :default ? nil : prefix
          root_hoisted[xmlns_key] = uri
          input_formats[uri] = format

          # NEW: Build per-prefix-URI format
          key = prefix ? "#{prefix}:#{uri}" : ":#{uri}"
          input_prefix_formats[key] = format
        end

        # Build global prefix registry from ALL locations
        registry = {}
        namespaces_with_locations.each_value do |ns_hash|
          ns_hash.each_value do |ns_config|
            if ns_config[:format] == :prefix && ns_config[:prefix]
              registry[ns_config[:uri]] = ns_config[:prefix]
            end
            # Track format for all namespaces
            input_formats[ns_config[:uri]] ||= ns_config[:format] || :default

            # NEW: Build per-prefix-URI format for all locations
            prefix = ns_config[:prefix]
            uri = ns_config[:uri]
            key = prefix ? "#{prefix}:#{uri}" : ":#{uri}"
            input_prefix_formats[key] =
              ns_config[:format] || (prefix ? :prefix : :default)
          end
        end

        # Build element node tree with location info
        root_node = ElementNode.new(
          qualified_name: mapping.root_element || "",
          use_prefix: nil,
          hoisted_declarations: root_hoisted,
        )

        # Store location data for use during serialization
        # This is the KEY addition - tracking WHERE namespaces were declared
        location_data = {}
        namespaces_with_locations.each do |path, ns_hash|
          next if path.empty? # Root already handled

          # Convert path array to string key for storage
          path_key = path.join("/")
          hoisted = {}
          ns_hash.each_value do |ns_config|
            prefix = ns_config[:prefix]
            uri = ns_config[:uri]
            format = ns_config[:format] || (prefix ? :prefix : :default)
            xmlns_key = format == :default ? nil : prefix
            hoisted[xmlns_key] = uri
          end
          location_data[path_key] = hoisted
        end

        plan = new(root_node: root_node, global_prefix_registry: registry,
                   input_formats: input_formats,
                   input_prefix_formats: input_prefix_formats)
        plan.instance_variable_set(:@namespace_locations, location_data)
        plan
      end

      # Get namespace declarations at a specific element path
      #
      # @param path [Array<String>] Element path (e.g., ["child", "grandchild"])
      # @return [Hash, nil] Namespace declarations at that path, or nil if none
      def namespaces_at_path(path)
        return nil unless @namespace_locations

        path_key = path.join("/")
        @namespace_locations[path_key]
      end

      # Check if a namespace was declared at a specific path in the input
      #
      # @param uri [String] Namespace URI to check
      # @param path [Array<String>] Element path
      # @return [Boolean] True if namespace was declared at this path
      def namespace_declared_at_path?(uri, path)
        ns_at_path = namespaces_at_path(path)
        return false unless ns_at_path

        ns_at_path.value?(uri)
      end

      # Get namespace declarations as a Hash
      #
      # Converts hoisted_declarations into NamespaceDeclaration objects
      # for querying and inspection.
      #
      # @return [Hash<String, NamespaceDeclaration>] Map of namespace key => declaration
      def namespaces
        # Performance: Return cached result if available
        return @namespaces_cache if @namespaces_cache

        return {} unless @namespace_classes

        result = {}
        @namespace_classes.each do |uri, ns_class|
          key = ns_class.to_key

          # Determine format by checking hoisted_declarations
          # Priority: input_formats (for preservation) > hoisted_declarations (actual format) > default
          format = @input_formats[uri]
          prefix_override = nil
          unless format
            # Check hoisted_declarations to see what format is actually being used
            # hoisted_declarations keys: nil = default format, "prefix" = prefix format
            hoisted_key = @root_node.hoisted_declarations.key(uri)

            if @root_node.hoisted_declarations.value?(uri)
              # Namespace IS in hoisted_declarations - check what key it has
              hoisted_key = @root_node.hoisted_declarations.key(uri)
              if hoisted_key.nil?
                # Namespace found with nil key = default format
                format = :default
              else
                # Namespace found with prefix key = prefix format
                format = :prefix
                # Set prefix_override to the actual prefix being used
                prefix_override = hoisted_key
              end
            else
              # Namespace NOT found in hoisted_declarations, use default logic
              # For root elements, prefer default format unless namespace has prefix_default and no hoisted
              format = ns_class.prefix_default ? :prefix : :default
            end
          end

          # Check if this format came from input (for from_input? method)
          from_input = @input_formats.key?(uri)

          data = NamespaceDeclarationData.new(
            namespace_class: ns_class,
            format: format,
            declared_at: :here,
            source: from_input ? :input : nil,
            prefix_override: prefix_override,
          )
          result[key] = NamespaceDeclaration.new(data)
        end
        # Performance: Cache the result
        @namespaces_cache = result
      end

      # Get a specific namespace declaration by key
      #
      # @param key [String] Namespace key (e.g., namespace class to_key)
      # @return [NamespaceDeclaration, nil] Namespace declaration or nil if not found
      def namespace(key)
        namespaces[key]
      end

      # Get namespace declaration by namespace class
      #
      # @param ns_class [Class] Namespace class to look up
      # @return [NamespaceDeclaration, nil] Namespace declaration or nil if not found
      def namespace_for_class(ns_class)
        return nil unless ns_class && @namespace_classes

        # Find the URI for this namespace class
        uri = @namespace_classes.key(ns_class)
        return nil unless uri

        # Get the namespace using the class's to_key method
        namespace(ns_class.to_key)
      end

      # Performance: O(1) namespace lookup by URI
      #
      # @param uri [String] Namespace URI to search for
      # @return [Hash, nil] Namespace info hash or nil
      def find_namespace_by_uri(uri)
        return nil unless uri

        # Build cache on first access
        unless @uri_to_info_cache
          @uri_to_info_cache = {}
          @root_node.hoisted_declarations.each do |xmlns_key, xmlns_uri|
            @uri_to_info_cache[xmlns_uri] = {
              prefix: xmlns_key,
              format: xmlns_key ? :prefix : :default,
              declared_at: :here,
              uri: xmlns_uri,
            }
          end
        end

        @uri_to_info_cache[uri]
      end

      # Get child element plan by attribute name
      #
      # @param name [Symbol] Child attribute name
      # @return [DeclarationPlan, nil] Child plan or nil if not found
      def child_plan(name)
        @children_plans&.dig(name)
      end

      # Collect all namespace classes in the tree that have schema_location
      #
      # @return [Array<Class>] Array of namespace classes with schema_location
      def namespaces_with_schema_location
        return [] unless @namespace_classes

        ns_classes = []
        collect_ns_classes_recursive(@root_node, ns_classes)
        ns_classes.uniq.select do |ns_class|
          ns_class.respond_to?(:schema_location) && ns_class.schema_location
        end
      end

      # Recursively collect namespace classes from element nodes
      #
      # @param element_node [ElementNode] Current element node
      # @param ns_classes [Array<Class>] Accumulator for namespace classes
      # @return [void]
      def collect_ns_classes_recursive(element_node, ns_classes)
        # Add namespace from element's own namespace_class
        if element_node.respond_to?(:qualified_name) && @namespace_classes
          # Try to find namespace class from namespace_classes by matching URI
          # The ElementNode itself doesn't store ns_class, but we can check if
          # any of our namespace_classes match the element's context
        end

        # Recursively collect from children
        element_node.element_nodes.each do |child_node|
          collect_ns_classes_recursive(child_node, ns_classes)
        end
      end

      # Get the XSI prefix from hoisted_declarations
      #
      # @return [String, nil] The prefix for XSI namespace if found
      def xsi_prefix
        return nil unless @root_node&.hoisted_declarations

        @root_node.hoisted_declarations.each do |prefix, uri|
          return prefix if uri == W3c::XsiNamespace.uri
        end
        nil
      end
    end
  end
end
