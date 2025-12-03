require "set"

module Lutaml
  module Model
    class Collection < Lutaml::Model::Serializable
      include Enumerable

      class << self
        INHERITED_ATTRIBUTES = %i[
          instance_type
          instance_name
          sort_by_field
          sort_direction
          indexes
          collection_validations
        ].freeze

        ALLOWED_OPTIONS = %i[polymorphic].freeze

        def inherited(subclass)
          super

          INHERITED_ATTRIBUTES.each do |var|
            subclass.instance_variable_set(
              :"@#{var}",
              instance_variable_get(:"@#{var}"),
            )
          end
        end

        attr_reader :instance_type,
                    :instance_name,
                    :sort_by_field,
                    :sort_direction,
                    :indexes
                    :sort_direction,
                    :collection_validations

        def instances(name, type, options = {}, &block)
          if (invalid_opts = options.keys - ALLOWED_OPTIONS).any?
            raise Lutaml::Model::InvalidAttributeOptionsError.new(name,
                                                                  invalid_opts)
          end

          attribute(name, type, collection: true, validations: block, **options)

          @instance_type = Lutaml::Model::Attribute.cast_type!(type)
          @instance_name = name

          define_method(:"#{name}=") do |collection|
            self.collection = collection
          end
        end

        def sort(by:, order: :asc)
          @sort_by_field = by.is_a?(Proc) ? by : by.to_sym
          @sort_direction = order

          check_sort_configs! if @mappings[:xml]
        end

        alias_method :ordered, :sort

        def sort_configured?
          !!@sort_by_field
        end

        # Index by one or more fields for O(1) lookups
        # Example: index_by :id, :email
        def index_by(*fields)
          @indexes ||= {}
          fields.each do |field|
            if field.is_a?(Proc)
              raise ArgumentError,
                    "Proc indexes require a name. Use: index :name, by: ->(item) { ... }"
            end
            @indexes[field.to_sym] = field.to_sym
          end
        end

        # Named index with optional proc for custom key extraction
        # Example: index :email, by: ->(item) { item.email.downcase }
        def index(name, by:)
          @indexes ||= {}
          @indexes[name.to_sym] = by
        end

        def index_configured?
          @indexes && !@indexes.empty?
        end

        # Define collection-level validations
        def validate_collection(&block)
          @collection_validations ||= []
          @collection_validations << block if block
        end

        # Validate uniqueness of a field across all instances in the collection
        def validates_uniqueness_of(field, message: nil)
          validate_collection do |collection, errors|
            duplicates = find_duplicate_values(collection, field)
            add_uniqueness_error(errors, field, duplicates, message) if duplicates.any?
          end
        end

        # Validate minimum count requirement
        def validates_min_count(count, message: nil)
          validate_collection do |collection, errors|
            if collection.size < count
              default_message = "collection must have at least #{count} items, but has #{collection.size}"
              errors.add(:collection, message || default_message)
            end
          end
        end

        # Validate maximum count requirement
        def validates_max_count(count, message: nil)
          validate_collection do |collection, errors|
            if collection.size > count
              default_message = "collection must have at most #{count} items, but has #{collection.size}"
              errors.add(:collection, message || default_message)
            end
          end
        end

        # Validate that all instances have a specific attribute
        def validates_all_present(field, message: nil)
          validate_collection do |collection, errors|
            missing_items = collection.select do |instance|
              value = instance.respond_to?(field) ? instance.public_send(field) : nil
              Utils.blank?(value)
            end

            unless missing_items.empty?
              default_message = "all items must have #{field}, but #{missing_items.size} items are missing it"
              errors.add(:collection, message || default_message)
            end
          end
        end

        def to(format, instance, options = {})
          mappings = mappings_for(format)

          if mappings.no_root? && format == :xml
            mappings.mappings.map do |mapping|
              serialize_for_mapping(mapping, instance, format, options)
            end.join("\n")
          else
            super(format, instance, options.merge(collection: true))
          end
        end

        def serialize_for_mapping(mapping, instance, format, options)
          options[:tag_name] = mapping.name

          attr_value = instance.public_send(mapping.to)
          return if attr_value.nil? || attr_value.empty?

          # Handle custom Collection classes - extract the actual items array
          if attr_value.is_a?(Lutaml::Model::Collection)
            attr_value = attr_value.collection
          end

          attr_value = [attr_value] unless attr_value.is_a?(Array)
          attr_value.map { |v| v.public_send(:"to_#{format}", options) }
        end

        def as(format, instance, options = {})
          mappings = mappings_for(format)
          data = super

          if mappings.no_root? && format != :xml && !mappings.root_mapping
            # Convert KeyValueElement to Hash if needed
            hash = data.is_a?(Hash) ? data : data.to_hash
            # Handle "__root__" wrapper for key-value formats (created by transformation)
            hash = hash["__root__"] if hash.key?("__root__")
            result = Utils.fetch_str_or_sym(hash, instance_name)

            # Extract values from nested hashes with empty string keys
            # (created by transformation for simple models with single attribute)
            if result.is_a?(Array)
              result = result.map do |item|
                if item.is_a?(Hash) && item.key?("") && item.size == 1
                  item[""]
                else
                  item
                end
              end
            end

            result
          else
            data
          end
        end

        def from(format, data, options = {})
          mappings = mappings_for(format)
          if mappings.no_root? && format == :xml
            tag_name = mappings.find_by_to!(instance_name).name
            data = "<#{tag_name}>#{data}</#{tag_name}>"
          end

          super(format, data, options.merge(from_collection: true))
        end

        def of(format, data, options = {})
          mappings = mappings_for(format)

          if mappings.no_root? && format != :xml && !mappings.root_mapping
            data = { mappings.find_by_to!(instance_name).name => data }
          end

          super(format, data, options.merge(from_collection: true))
        end

        def apply_mappings(data, format, options = {})
          super(data, format, options.merge(collection: true))
        end

        private

        def find_duplicate_values(collection, field)
          seen_values = Set.new
          duplicates = Set.new

          collection.each do |instance|
            value = extract_field_value(instance, field)
            next if value.nil?

            if seen_values.include?(value)
              duplicates.add(value)
            else
              seen_values.add(value)
            end
          end

          duplicates
        end

        def extract_field_value(instance, field)
          instance.respond_to?(field) ? instance.public_send(field) : nil
        end

        def add_uniqueness_error(errors, field, duplicates, message)
          default_message = "#{field} values must be unique across collection, found duplicates: #{duplicates.to_a.join(', ')}"
          errors.add(:collection, message || default_message)
        end
      end

      attr_reader :__register

      def initialize(items = [],
__register: Lutaml::Model::Config.default_register)
        super()

        @__register = __register
        items = [items].compact unless items.is_a?(Array)

        type = Lutaml::Model::GlobalContext.resolve_type(
          self.class.instance_type, @__register
        )
        self.collection = items.map do |item|
          if item.is_a?(type) || item.is_a?(Lutaml::Model::Serializable)
            item
          elsif type <= Lutaml::Model::Type::Value
            type.cast(item)
          else
            type.new(item)
          end
        end

        sort_items!
        build_index_caches!
      end

      def to_format(format, options = {})
        super(format, options.merge(collection: true))
      end

      def collection
        instance_variable_get(:"@#{self.class.instance_name}")
      end

      def collection=(collection)
        instance_variable_set(:"@#{self.class.instance_name}", collection)
        sort_items!
        build_index_caches!
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

      def each(&)
        collection.each(&)
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
        build_index_caches!
      end

      def [](index)
        collection[index]
      end

      def []=(index, value)
        collection[index] = value
        sort_items!
        build_index_caches!
      end

      def empty?
        collection&.empty?
      end

      def order_defined?
        self.class.sort_configured?
      end

      def sort_items!
        return if collection.nil?
        return unless order_defined?
        return if collection.one?

        apply_sort!
        collection.reverse! if self.class.sort_direction == :desc
      end

      # Index methods for O(1) lookups

      # @return [Hash, nil] Hash of { field_name => { key => item } } or nil
      attr_reader :index_caches

      # Build index caches for all configured indexes
      def build_index_caches!
        return unless self.class.index_configured?
        return if collection.nil? || collection.empty?

        @index_caches = {}

        self.class.indexes.each do |name, field_or_proc|
          @index_caches[name] = {}

          collection.each do |item|
            key = if field_or_proc.is_a?(Proc)
                    field_or_proc.call(item)
                  else
                    item.send(field_or_proc)
                  end
            @index_caches[name][key] = item
          end
        end
      end

      # Find an item by index field and key
      # @param field [Symbol] The index field name
      # @param key [Object] The key to look up
      # @return [Object, nil] The item or nil if not found
      def find_by(field, key)
        return nil unless @index_caches

        cache = @index_caches[field.to_sym]
        cache&.fetch(key, nil)
      end

      # Fetch an item by key (only for single-index collections)
      # @param key [Object] The key to look up
      # @return [Object, nil] The item or nil if not found
      # @raise [ArgumentError] If multiple indexes are configured
      def fetch(key)
        unless self.class.indexes&.one?
          raise ArgumentError,
                "#fetch only works with single index. Use #find_by(field, key)"
        end

        field = self.class.indexes.keys.first
        find_by(field, key)
      end

      def apply_sort!
        field = self.class.sort_by_field

        if field.is_a?(Proc)
          collection.sort_by!(&field)
        else
          collection.sort_by! { |item| item.send(field) }
        end
      end

      # Override validate to support both instance and collection-level validations
      def validate(register: Lutaml::Model::Config.default_register)
        errors = []

        # Run standard instance-level validations first (inherited from Serializable)
        errors.concat(super)

        # Run collection-level validations
        errors.concat(validate_collection_rules)

        errors
      end

      private

      def validate_collection_rules
        return [] unless self.class.collection_validations

        errors = Errors.new
        collection_items = collection || []

        self.class.collection_validations.each do |validation_block|
          validation_block.call(collection_items, errors)
        end

        errors.messages.map { |msg| ValidationFailedError.new([msg]) }
      end
    end
  end
end
