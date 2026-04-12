module Lutaml
  module Model
    # Internal context class for validation chaining.
    # Allows validations to communicate state and share results.
    # This is an internal API - its interface may change.
    class ValidationContext
      attr_reader :errors, :metadata

      def initialize
        @errors = []
        @stopped = false
        @metadata = {}
      end

      # Check if the validation chain has been stopped
      def stopped?
        @stopped
      end

      # Stop the validation chain - subsequent validations will not run
      def stop!
        @stopped = true
      end

      # Store metadata that can be accessed by subsequent validations
      # @param key [Symbol] The key to store
      # @param value [Object] The value to store
      def [](key)
        @metadata[key]
      end

      # Retrieve metadata stored by previous validations
      # @param key [Symbol] The key to retrieve
      # @param value [Object] The value to store
      def []=(key, value)
        @metadata[key] = value
      end

      # Check if any validation has added errors
      def failed?
        @errors.any?
      end

      # Record that this context received errors
      # @param error_list [Array] List of error messages
      def add_errors(error_list)
        @errors.concat(error_list)
      end
    end

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
          organization
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
                    :indexes,
                    :collection_validations,
                    :organization

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

        # Declare that this Collection produces organized instances of a GroupClass.
        #
        # @param name [Symbol] attribute name on the Collection
        # @param group_class [Class] the GroupClass type
        def organizes(name, group_class)
          attribute(name, group_class, collection: true)
          @organization = Organization.new(name, group_class)
        end

        def sort(by:, order: :asc)
          @sort_by_field = by.is_a?(Proc) ? by : by.to_sym
          @sort_direction = order

          check_sort_configs!
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
        #
        # @overload validate_collection(&block)
        #   Define a custom validation block
        #   @param block [Proc] Block receiving (collection, errors, context)
        #
        # @overload validate_collection(if_cond:, &block)
        #   Define a conditional validation that only runs if the condition is met
        #   @param if_cond [Proc] Block receiving (context) - validation runs if it returns true
        #   @param block [Proc] Block receiving (collection, errors, context)
        #
        # @overload validate_collection(unless_cond:, &block)
        #   Define a conditional validation that runs unless the condition is met
        #   @param unless_cond [Proc] Block receiving (context) - validation skips if it returns true
        #   @param block [Proc] Block receiving (collection, errors, context)
        #
        # @example Basic usage
        #   validate_collection do |collection, errors, ctx|
        #     # Custom validation logic
        #   end
        #
        # @example Conditional execution based on context state
        #   validate_collection do |collection, errors, ctx|
        #     # Only run if uniqueness validation passed
        #     return if ctx[:duplicates_found]
        #     # Expensive cross-reference check...
        #   end
        #
        # @example Conditional validation with :if_cond option
        #   validate_collection(if_cond: ->(ctx) { !ctx[:skip_expensive_checks] }) do |collection, errors|
        #     # This only runs when ctx[:skip_expensive_checks] is falsy
        #   end
        #
        # @example Sharing results between validations
        #   validates_uniqueness_of :id  # Stores duplicates in ctx[:duplicates_of_id]
        #
        #   validate_collection do |collection, errors, ctx|
        #     if ctx[:duplicates_of_id]&.any?
        #       errors.add(:collection, "Found duplicates that prevent cross-validation")
        #     end
        #   end
        #
        def validate_collection(if_cond: nil, unless_cond: nil, &block)
          @collection_validations ||= []
          return unless block

          options = { if_cond: if_cond, unless_cond: unless_cond }
          @collection_validations << [block, options]
        end

        # Validate uniqueness of a field across all instances in the collection
        #
        # @param field [Symbol] The attribute name to check for uniqueness
        # @param message [String, nil] Custom error message
        #
        # @example Basic uniqueness
        #   validates_uniqueness_of :id
        #
        # @example With custom message
        #   validates_uniqueness_of :email, message: "Email addresses must be unique"
        #
        # @example Using context in subsequent validations
        #   validates_uniqueness_of :id  # Stores duplicate values in ctx[:duplicates_of_id]
        #
        #   validate_collection do |collection, errors, ctx|
        #     return if ctx[:duplicates_of_id].nil? || ctx[:duplicates_of_id].empty?
        #     # Handle the duplicate IDs...
        #   end
        #
        def validates_uniqueness_of(field, message: nil)
          validate_collection(if_cond: ->(ctx) {
            !ctx.stopped?
          }) do |collection, errors, ctx|
            duplicates = find_duplicate_values(collection, field)

            # Store duplicates in context for potential use by other validations
            ctx[:"duplicates_of_#{field}"] = duplicates

            if duplicates.any?
              add_uniqueness_error(errors, field, duplicates, message)
              ctx.add_errors(errors.messages)
            end
          end
        end

        # Validate minimum count requirement
        #
        # @param count [Integer] Minimum number of items required
        # @param message [String, nil] Custom error message
        #
        # @example Basic minimum count
        #   validates_min_count 1, message: "At least one item is required"
        #
        def validates_min_count(count, message: nil)
          validate_collection(if_cond: ->(ctx) {
            !ctx.stopped?
          }) do |collection, errors, ctx|
            if collection.size < count
              default_message = "collection must have at least #{count} items, but has #{collection.size}"
              errors.add(:collection, message || default_message)
              ctx.add_errors(errors.messages)
            end
          end
        end

        # Validate maximum count requirement
        #
        # @param count [Integer] Maximum number of items allowed
        # @param message [String, nil] Custom error message
        #
        # @example Basic maximum count
        #   validates_max_count 100, message: "Cannot exceed 100 items"
        #
        def validates_max_count(count, message: nil)
          validate_collection(if_cond: ->(ctx) {
            !ctx.stopped?
          }) do |collection, errors, ctx|
            if collection.size > count
              default_message = "collection must have at most #{count} items, but has #{collection.size}"
              errors.add(:collection, message || default_message)
              ctx.add_errors(errors.messages)
            end
          end
        end

        # Validate that all instances have a specific attribute
        #
        # @param field [Symbol] The attribute name that must be present on all items
        # @param message [String, nil] Custom error message
        #
        # @example Basic presence validation
        #   validates_all_present :author, message: "All items must have an author"
        #
        # @example Checking context in subsequent validation
        #   validates_all_present :email  # Sets ctx[:missing_email_count] if items are missing email
        #
        #   validate_collection do |collection, errors, ctx|
        #     if ctx[:missing_email_count].to_i > 5
        #       errors.add(:collection, "Too many items missing email addresses")
        #     end
        #   end
        #
        def validates_all_present(field, message: nil)
          validate_collection(if_cond: ->(ctx) {
            !ctx.stopped?
          }) do |collection, errors, ctx|
            missing_items = collection.select do |instance|
              value = instance.respond_to?(field) ? instance.public_send(field) : nil
              Utils.blank?(value)
            end

            # Store count in context for downstream validations
            ctx[:"missing_#{field}_count"] = missing_items.size

            unless missing_items.empty?
              default_message = "all items must have #{field}, but #{missing_items.size} items are missing it"
              errors.add(:collection, message || default_message)
              ctx.add_errors(errors.messages)
            end
          end
        end

        def to(format, instance, options = {})
          mappings = mappings_for(format)

          if mappings.no_root? && collection_no_root_to?(format)
            collection_no_root_to(format, mappings, instance, options)
          else
            super(format, instance, options.merge(collection: true))
          end
        end

        def as(format, instance, options = {})
          mappings = mappings_for(format)
          data = super

          if !collection_structured_format?(format) && mappings.no_root? && !mappings.root_mapping
            unwrap_no_root_data(data)
          else
            data
          end
        end

        def from(format, data, options = {})
          mappings = mappings_for(format)

          if collection_structured_format?(format) && mappings.no_root?
            data = wrap_no_root_input(format, mappings, data)
          end

          super(format, data, options.merge(from_collection: true))
        end

        def of(format, data, options = {})
          mappings = mappings_for(format)

          if !collection_structured_format?(format) && mappings.no_root? && !mappings.root_mapping
            data = { mappings.find_by_to!(instance_name).name => data }
          end

          super(format, data, options.merge(from_collection: true))
        end

        # Hook: returns true for formats that use structured (tree-based) serialization
        # like XML. Key-value formats (JSON, YAML, TOML) return false (default).
        # XML overrides to return true.
        def collection_structured_format?(_format)
          false
        end

        # Hook: returns true if this format handles no_root serialization specially.
        # XML overrides to return true for :xml format.
        def collection_no_root_to?(_format)
          false
        end

        # Hook for structured-format no_root serialization (e.g., XML).
        # XML overrides to serialize each mapping separately.
        def collection_no_root_to(_format, _mappings, _instance, _options)
          raise NotImplementedError
        end

        # Hook for structured-format no_root input wrapping (e.g., XML).
        # XML overrides to wrap raw data in a fake root tag.
        def wrap_no_root_input(_format, _mappings, data)
          data
        end

        def apply_mappings(data, format, options = {})
          super(data, format, options.merge(collection: true))
        end

        private

        def unwrap_no_root_data(data)
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
        end

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

      attr_reader :lutaml_register

      def initialize(items = [],
lutaml_register: Lutaml::Model::Config.default_register)
        super()

        @lutaml_register = lutaml_register
        items = [items].compact unless items.is_a?(Array)

        type = Lutaml::Model::GlobalContext.resolve_type(
          self.class.instance_type, @lutaml_register
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
      #
      # Collection-level validations run in order and can share state through a
      # context object. Validations can stop the chain early by calling ctx.stop!
      # or by checking ctx[:some_key] to see results from previous validations.
      #
      # @return [Array<Lutaml::Model::ValidationFailedError>] List of validation errors
      #
      # @example Standard usage
      #   collection.validate  # Returns array of errors, doesn't raise
      #   collection.validate! # Raises if any errors found
      #
      # @example With chaining (context)
      #   class PublicationCollection < Lutaml::Model::Collection
      #     instances :publications, Publication
      #
      #     validates_uniqueness_of :id  # Stores ctx[:duplicates_of_id]
      #
      #     validate_collection do |collection, errors, ctx|
      #       # Check if uniqueness validation found duplicates
      #       return if ctx[:duplicates_of_id].nil? || ctx[:duplicates_of_id].empty?
      #
      #       # Skip expensive validation if duplicates exist
      #       errors.add(:collection, "Cannot run expensive checks with duplicate IDs")
      #     end
      #   end
      #
      def validate(register: Lutaml::Model::Config.default_register)
        errors = []

        # Run standard instance-level validations first (inherited from Serializable)
        errors.concat(super)

        # Run collection-level validations with context for chaining
        errors.concat(validate_collection_rules)

        errors
      end

      private

      def validate_collection_rules
        return [] unless self.class.collection_validations

        errors = Errors.new
        collection_items = collection || []
        context = ValidationContext.new

        self.class.collection_validations.each do |validation_block, options|
          # Check stop condition
          break if context.stopped?

          # Evaluate conditional options
          next if options[:if_cond] && !options[:if_cond].call(context)
          next if options[:unless_cond]&.call(context)

          # Build block arguments based on arity for backwards compatibility
          # Old blocks: |collection, errors|
          # New blocks:  |collection, errors, context|
          begin
            case validation_block.arity
            when 1
              validation_block.call(collection_items)
            when 2
              validation_block.call(collection_items, errors)
            else
              validation_block.call(collection_items, errors, context)
            end
          rescue LocalJumpError
            # ctx.stop! was called via `return` - this is a valid pattern
            context.stop!
          end

          # Update context with current errors
          context.add_errors(errors.messages)
        end

        errors.messages.map { |msg| ValidationFailedError.new([msg]) }
      end
    end
  end
end
