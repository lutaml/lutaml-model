# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # Resolves type namespace references from attributes
      #
      # LAZY RESOLUTION (Session 126):
      # Type namespaces are resolved during declaration planning, not collection.
      # This prevents infinite recursion: collection → type_namespace_class → imports → new collection
      # Safe to call type_namespace_class during planning - all mappings already imported.
      #
      # @example
      #   resolver = TypeNamespaceResolver.new
      #   resolver.resolve(needs)
      #
      class TypeNamespaceResolver
        # Initialize resolver with register for type resolution
        #
        # @param register [Symbol] the register ID for type resolution
        def initialize(register = nil)
          @register = register || Lutaml::Model::Config.default_register
        end

        # Resolve type namespace references collected during NamespaceCollector phase
        #
        # Populates needs.type_namespaces, needs.type_namespace_classes,
        # needs.type_attribute_namespaces, needs.type_element_namespaces
        # from needs.type_refs
        #
        # @param needs [NamespaceNeeds] Namespace needs structure with type_refs
        # @return [void]
        def resolve(needs)
          type_refs = needs.type_refs
          return unless type_refs&.any?

          type_refs.each do |ref|
            attr_def = ref.attribute
            attr_rule = ref.rule
            context = ref.context

            # NOW it's safe to call type_namespace_class - all mappings already imported
            type_ns_class = attr_def.type_namespace_class(@register)
            next unless type_ns_class

            # Populate needs just like collector would have
            needs.add_type_namespace(attr_rule.to, type_ns_class)

            if context == :attribute
              needs.add_type_attribute_namespace(type_ns_class)
              usage = :attributes
            else
              needs.add_type_element_namespace(type_ns_class)
              usage = :elements
            end

            # Track in namespaces hash
            key = type_ns_class.to_key
            usage_obj = needs.namespace(key) || NamespaceUsage.new(type_ns_class)
            usage_obj.used_in << usage
            needs.add_namespace(key, usage_obj)
          end

          # Clear type_refs after resolution (no longer needed)
          needs.clear_type_refs

          # Recursively resolve children
          needs.children&.each_value do |child_needs|
            resolve(child_needs)
          end
        end

        private

        attr_reader :register
      end
    end
  end
end
