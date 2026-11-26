# frozen_string_literal: true

module Lutaml
  module Lml
    # The parsed LML document model.
    class Document < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      # Non-serialized navigation index (definitions and uses).
      def symbols
        @symbols ||= SymbolIndex.new(self)
      end

      # Core attributes
      attribute :name, :string
      attribute :lml_version, :string
      attribute :title, :string
      attribute :caption, :string
      attribute :groups, "Lutaml::Lml::Group", collection: true, default: -> { [] }
      attribute :fidelity, "Lutaml::Lml::Fidelity"
      attribute :fontname, :string
      attribute :comments, :string, collection: true, default: -> { [] }

      attribute :classes, "Lutaml::Lml::UmlClass", collection: true, default: -> { [] }
      attribute :data_types, "Lutaml::Lml::DataType", collection: true, default: -> { [] }
      attribute :enums, "Lutaml::Lml::Enum", collection: true, default: -> { [] }
      attribute :packages, "Lutaml::Lml::Package", collection: true, default: -> { [] }
      attribute :namespaces, "Lutaml::Lml::Namespace", collection: true, default: -> { [] }
      # `models <Name> version "x.y.z"` headers: model name -> declared
      # version (issue #16, the co-release identity line).
      attribute :model_versions, :hash, default: -> { {} }
      attribute :serialization_mappings, "Lutaml::Lml::SerializationMapping", collection: true, default: -> { [] }
      attribute :primitives, "Lutaml::Lml::PrimitiveType", collection: true, default: -> { [] }
      attribute :associations, "Lutaml::Lml::Association", collection: true, default: -> { [] }
      attribute :diagrams, "Lutaml::Lml::Diagram", collection: true, default: -> { [] }

      # LML-specific. instance/instances/fidelity/show_filter/hide_filter
      # are deliberately default-less: nil means "absent".
      attribute :instance, "Lutaml::Lml::Instance"
      attribute :requires, :string, collection: true, default: -> { [] }
      attribute :instances, "Lutaml::Lml::InstanceCollection"

      # Repeated `instances` blocks accumulate (issue #17): instances,
      # imports, exports and collections concat; a duplicate collection
      # name is an error (same name is a mistake, distinct names intent).
      def instances=(collection)
        collection = Lutaml::Lml::InstanceCollection.new(**collection) if collection.is_a?(Hash)
        if @instances.nil? || (@instances.instances.empty? && @instances.imports.empty? &&
            @instances.exports.empty? && @instances.collections.empty?)
          @instances = collection
        else
          merge_instances(collection)
        end
      end

      def merge_instances(incoming)
        names = @instances.collections.map(&:name)
        incoming.collections.each do |collection|
          raise Lutaml::Lml::Error, "duplicate collection name '#{collection.name}'" if names.include?(collection.name)
        end
        @instances.instances.concat(incoming.instances)
        @instances.imports.concat(incoming.imports)
        @instances.exports.concat(incoming.exports)
        @instances.collections.concat(incoming.collections)
      end
      attribute :view_imports, "Lutaml::Lml::ViewImport", collection: true, default: -> { [] }
      attribute :show_filter, "Lutaml::Lml::ViewFilter"
      attribute :hide_filter, "Lutaml::Lml::ViewFilter"

      # All class-like entities on the document. Used by resolvers and
      # formatters that need to walk every classifiable type without
      # caring which collection holds it.
      def all_classes
        EntityTypes.all.flat_map { |type| public_send(type.entity_type) }
      end

      # Class-like entities that can own associations. Excludes enums
      # (which have no attributes/associations of their own).
      def classifiable_classes
        EntityTypes.classifiable.flat_map { |type| public_send(type.entity_type) }
      end
    end
  end
end
