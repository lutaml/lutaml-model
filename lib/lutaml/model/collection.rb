module Lutaml
  module Model
    class Collection < Lutaml::Model::Serializable
      include Enumerable

      class << self
        attr_reader :instance_type,
                    :instance_name,
                    :order_by_field,
                    :order_direction

        def instances(name, type, &block)
          attribute(name, type, collection: true, validations: block)

          @instance_type = type
          @instance_name = name
        end

        def ordered(by:, order: :asc)
          @order_by_field = by.to_sym
          @order_direction = order
        end

        def sort_configured?
          !!@order_by_field
        end

        def to(format, instance, options = {})
          mappings = mappings_for(format)

          if mappings.no_root? && format == :xml
            mappings.mappings.map do |mapping|
              serialize_for_mapping(mapping, instance, format, options)
            end.flatten.join("\n")
          else
            super(format, instance, options.merge(collection: true))
          end
        end

        def serialize_for_mapping(mapping, instance, format, options)
          options[:tag_name] = mapping.name

          attr_value = instance.public_send(mapping.to)
          return if attr_value.nil? || attr_value.empty?

          attr_value = [attr_value] unless attr_value.is_a?(Array)
          attr_value.map { |v| v.public_send(:"to_#{format}", options) }
        end

        def as(format, instance, options = {})
          mappings = mappings_for(format)
          data = super

          if mappings.no_root? && format != :xml && !mappings.root_mapping
            Utils.fetch_with_string_or_symbol_key(data, mappings.mappings.first.to)
          else
            data
          end
        end

        def from(format, data, options = {})
          mappings = mappings_for(format)
          if mappings.no_root? && format == :xml
            tag_name = mappings.find_by_to(instance_name).name
            data = "<#{tag_name}>#{data}</#{tag_name}>"
          end

          super(format, data, options.merge(from_collection: true))
        end

        def of(format, data, options = {})
          mappings = mappings_for(format)

          if mappings.no_root? && format != :xml && !mappings.root_mapping
            data = { mappings.find_by_to(instance_name).name => data }
          end

          super(format, data, options.merge(from_collection: true))
        end

        def apply_mappings(data, format, options = {})
          super(data, format, options.merge(collection: true))
        end
      end

      def initialize(items = [])
        super()
        items = [items].compact unless items.is_a?(Array)

        self.collection = items.map do |item|
          type = self.class.instance_type

          if item.is_a?(type)
            item
          else
            type.new(item)
          end
        end
      end

      def to_format(format, options = {})
        super(format, options.merge(collection: true))
      end

      def collection
        instance_variable_get(:"@#{self.class.instance_name}")
      end

      def collection=(collection)
        instance_variable_set(:"@#{self.class.instance_name}", collection)
      end

      def union(other)
        self.class.new((items + other.items).uniq)
      end

      def intersection(other)
        self.class.new(items & other.items)
      end

      def difference(other)
        self.class.new(items - other.items)
      end

      def each(&block)
        collection.each(&block)
      end

      def size
        collection.size
      end

      def first
        collection.first
      end

      def last
        collection.last
      end

      def <<(item)
        push(item)
      end

      def push(item)
        collection.push(item)
        sort_items!
      end

      def [](index)
        collection[index]
      end

      def []=(index, value)
        collection[index] = value
        sort_items!
      end

      def empty?
        collection.empty?
      end

      def order_defined?
        self.class.sort_configured?
      end

      def sort_items!
        return unless order_defined?

        unless collection&.one?
          field = self.class.order_by_field
          direction = self.class.order_direction

          collection.sort_by! { |item| item.send(field) }
          collection.reverse! if direction == :desc
        end
      end
    end
  end
end
