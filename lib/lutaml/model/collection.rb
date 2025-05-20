module Lutaml
  module Model
    class Collection < Lutaml::Model::Serializable
      include Enumerable

      class << self
        def instances(name, type)
          attribute(name, type, collection: true)

          @instance_type = type
          @instance_name = name
        end

        def instance_name
          @instance_name
        end

        def instance_type
          @instance_type
        end

        def to(format, instance, options = {})
          mappings = mappings_for(format)

          if mappings.no_root? && format == :xml
            instance.map do |item|
              item.public_send(:"to_#{format}", options)
            end.join("\n")
          else
            super(format, instance, options.merge(collection: true))
          end
        end

        def as(format, instance, options = {})
          mappings = mappings_for(format)
          data = super

          if mappings.no_root? && format != :xml && !mappings.root_mapping
            data[mappings.mappings.first.to.to_sym] || data[mappings.mappings.first.to.to_s]
          else
            data
          end
        end

        def from(format, data, options = {})
          mappings = mappings_for(format)
          if mappings.no_root? && format == :xml
            tag_name = mappings.mappings.first.name
            data = "<#{tag_name}>#{data}</#{tag_name}>"
          end

          super(format, data, options.merge(from_collection: true))
        end

        def of(format, data, options = {})
          mappings = mappings_for(format)

          if mappings.no_root? && format != :xml && !mappings.root_mapping
            data = { mappings.mappings.first.name => data }
          end

          super(format, data, options.merge(from_collection: true))
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
        instance_variable_get("@#{self.class.instance_name}")
      end

      def collection=(collection)
        instance_variable_set("@#{self.class.instance_name}", collection)
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

      def [](index)
        collection[index]
      end

      def []=(index, value)
        collection[index] = value
      end

      def empty?
        collection.empty?
      end
    end
  end
end
