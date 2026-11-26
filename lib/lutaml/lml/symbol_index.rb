# frozen_string_literal: true

module Lutaml
  module Lml
    # A flat, positioned index of the document's symbols and the uses
    # that reference them. Backs navigation, hover, and completion in
    # tooling, and is available as Document#symbols.
    class SymbolIndex
      Entry = Struct.new(:name, :kind, :container, :position, :detail, :record,
                         keyword_init: true)

      # LSP SymbolKind values.
      KINDS = {
        package: 4, class: 5, method: 6, field: 8,
        enum: 10, instance: 19, enum_member: 22, data_type: 23
      }.freeze

      attr_reader :entries

      def initialize(document)
        @entries = []
        return unless document

        walk_document(document)
      end

      def definitions(name)
        @entries.select { |entry| entry.name.to_s == name.to_s }
      end

      def uses(name)
        token = name.to_s
        @entries.select do |entry|
          if entry.record.is_a?(TopElementAttribute)
            reference?(entry.record, token)
          elsif entry.record.is_a?(Instance)
            [entry.record.type.to_s, entry.record.isa.to_s].include?(token)
          else
            false
          end
        end
      end

      def attribute_entries
        @entries.select { |entry| entry.kind == :field }
      end

      def entity_entries
        @entries.reject { |entry| %i[field method enum_member].include?(entry.kind) }
      end

      def names
        @entries.map(&:name).compact.uniq
      end

      private

      def walk_document(document)
        walk_members(document, nil)
        walk_instance(document.instance, nil) if document.instance
        walk_collection(document.instances) if document.instances
      end

      def walk_members(owner, container)
        Array(owner.classes).each { |klass| walk_class(klass, container) }
        Array(owner.enums).each { |enum| walk_enum(enum, container) }
        Array(owner.data_types).each { |type| walk_data_type(type, container) }
        Array(owner.packages).each { |package| walk_package(package, container) }
      end

      def walk_package(package, container)
        name = package.name.to_s
        add(name, :package, container, package.source_position, nil, package)
        walk_members(package, name)
      end

      def walk_class(klass, container)
        name = klass.name.to_s
        add(name, :class, container, klass.source_position, parent_detail(klass), klass)
        Array(klass.attributes).each do |attribute|
          add(attribute.name, :field, name, attribute.source_position,
              attribute_detail(attribute), attribute)
        end
        Array(klass.operations).each do |operation|
          add(operation.name, :method, name, operation.source_position,
              operation_detail(operation), operation)
        end
        Array(klass.data_types).each { |type| walk_data_type(type, name) }
      end

      def walk_enum(enum, container)
        name = enum.name.to_s
        add(name, :enum, container, enum.source_position, nil, enum)
        Array(enum.attributes).each do |member|
          add(member.name, :enum_member, name, member.source_position,
              enum_member_detail(member), member)
        end
        Array(enum.member_fields).each do |field|
          add(field.name, :field, name, field.source_position,
              field.type.to_s, field)
        end
      end

      def walk_data_type(type, container)
        name = type.name.to_s
        add(name, :data_type, container, type.source_position, nil, type)
        Array(type.attributes).each do |attribute|
          add(attribute.name, :field, name, attribute.source_position,
              attribute_detail(attribute), attribute)
        end
      end

      def walk_collection(collection)
        return unless collection.is_a?(InstanceCollection)

        name = collection.name.to_s
        add(name, :package, nil, collection.source_position, 'instances', collection)
        Array(collection.instances).each { |instance| walk_instance(instance, name) }
      end

      def walk_instance(instance, container)
        name = instance_label(instance)
        add(name, :instance, container, instance.source_position, name, instance)
        Array(instance.attributes).each do |attribute|
          next if attribute.name.to_s.empty?

          add(attribute.name, :field, name, attribute.source_position,
              attribute_value_detail(attribute), attribute)
          Array(attribute.instances).each { |nested| walk_instance(nested, name) }
        end
        walk_instance(instance.instance, name) if instance.instance
      end

      def add(name, kind, container, position, detail, record)
        return if name.to_s.empty? || position.nil?

        @entries << Entry.new(
          name: name.to_s, kind: kind, container: container,
          position: position, detail: detail, record: record
        )
      end

      def parent_detail(klass)
        klass.parent_class.to_s.empty? ? nil : "< #{klass.parent_class}"
      end

      def attribute_detail(attribute)
        detail = attribute.type.to_s.dup
        cardinality = attribute.cardinality
        if cardinality
          max = cardinality.max.to_s
          detail << " [#{cardinality.min}#{"..#{max}" unless max.empty?}]"
        end
        detail.empty? ? nil : detail
      end

      def operation_detail(operation)
        params = Array(operation.owned_parameter)
                 .map { |param| "#{param.name}: #{param.type}" }.join(', ')
        detail = "(#{params})"
        detail += " : #{operation.return_type}" if operation.return_type.to_s != ''
        detail
      end

      def enum_member_detail(member)
        description = Array(member.attributes).find { |a| a.name == 'description' }
        description&.type&.to_s
      end

      def attribute_value_detail(attribute)
        value = attribute.value
        value = value.value if value.is_a?(LiteralValue)
        value.nil? ? attribute.type.to_s : value.to_s
      end

      def instance_label(instance)
        type = instance.type.to_s
        name = instance.name.to_s
        return name unless name.empty?
        return type unless type.empty?

        'instance'
      end

      def reference?(attribute, token)
        type = attribute.type.to_s
        return true if type == token || type.split('[]').first == token

        value = attribute.value
        value = value.value if value.is_a?(LiteralValue)
        return false unless value.is_a?(Hash)

        reference = value[:reference] || value['reference']
        return false unless reference

        reference.to_s.split('.').include?(token)
      end
    end
  end
end
