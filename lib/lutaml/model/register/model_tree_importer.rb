# frozen_string_literal: true

module Lutaml
  module Model
    # Imports an entire model tree into a register.
    #
    # Recursively walks the attribute graph and registers all types.
    # Optionally binds all types to a specific namespace.
    #
    # @example
    #   importer = ModelTreeImporter.new(register, namespace_class: SomeNamespace)
    #   registered = importer.import(RootModel)
    #
    # @api public
    class ModelTreeImporter
      # @return [Register] The register to import into
      attr_reader :register

      # @api public
      # @return [Class, nil] Optional namespace class for binding
      attr_reader :namespace_class

      # @api public
      # @return [Set<Class>] Set of visited classes to avoid cycles
      attr_reader :visited

      # @api public
      # Create a new model tree importer.
      #
      # @param register [Register] The register to import into
      # @param namespace_class [Class, nil] Optional namespace for binding
      def initialize(register, namespace_class: nil)
        @register = register
        @namespace_class = namespace_class
        @visited = Set.new
      end

      # @api public
      # Import a model tree starting from root_class.
      #
      # Recursively registers the root class and all nested attribute types.
      #
      # @param root_class [Class] The root model class
      # @return [Array<Class>] All registered classes
      def import(root_class)
        return [] if @visited.include?(root_class)

        @visited << root_class
        registered = []

        # Bind namespace if provided
        if @namespace_class
          @register.bind_namespace(@namespace_class)
        end

        # Register the root class
        @register.register_model(root_class)
        registered << root_class

        # Recursively register all attribute types
        if root_class.include?(Lutaml::Model::Serialize) ||
            root_class.include?(Lutaml::Model::Serializable)
          root_class.attributes.each_value do |attribute|
            registered.concat(import_attribute_type(attribute))
          end
        end

        registered
      end

      private

      # Import a type from an attribute.
      #
      # @param attribute [Attribute] The attribute to import from
      # @return [Array<Class>] Registered classes
      def import_attribute_type(attribute)
        type = attribute.unresolved_type
        return [] unless type.is_a?(Class)

        # Skip built-in types (Type::Value subclasses)
        return [] if type <= Lutaml::Model::Type::Value

        import(type)
      end
    end
  end
end
