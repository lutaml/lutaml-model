# frozen_string_literal: true

module Lutaml
  module Model
    module Utils
      class << self
        # Convert string to camel case
        def camel_case(str)
          return "" if str.nil? || str.empty?

          str.split("/").map { |part| camelize_part(part) }.join("::")
        end

        # Convert string to class name
        def classify(str)
          str = str.to_s.delete(".")
          str = str.sub(/^[a-z\d]*/) { |match| camel_case(match) || match }

          str.gsub("::", "/").gsub(%r{(?:_|-|(/))([a-z\d]*)}i) do
            word = Regexp.last_match(2)
            substituted = camel_case(word) || word
            Regexp.last_match(1) ? "::#{substituted}" : substituted
          end
        end

        # Convert string to snake case
        def snake_case(str)
          str = str.to_s.tr(".", "_")
          return str unless /[A-Z-]|::/.match?(str)

          str.gsub("::", "/")
            .gsub(/([A-Z]+)(?=[A-Z][a-z])|([a-z\d])(?=[A-Z])/) { "#{$1 || $2}_" }
            .tr("-", "_")
            .downcase
        end

        def initialized?(value)
          return true unless value.respond_to?(:initialized?)

          value.initialized?
        end

        def uninitialized?(value)
          !initialized?(value)
        end

        def present?(value)
          !blank?(value)
        end

        def blank?(value)
          value.respond_to?(:empty?) ? value.empty? : value.nil?
        end

        def empty_collection?(collection)
          return false if collection.nil?
          return false unless [Array, Hash].include?(collection.class)

          collection.empty?
        end

        def empty?(value)
          value.respond_to?(:empty?) ? value.empty? : false
        end

        # Check if the hash contains the given key in string or symbol format
        # @param hash [Hash] the hash to check
        # @param key [String, Symbol] the key to check
        # @return [Boolean] true if the hash contains the key, false otherwise
        # @example
        #   hash = { "key" => "value" }
        #   string_or_symbol_key?(hash, "key") # => true
        #   string_or_symbol_key?(hash, :key) # => true
        #   string_or_symbol_key?(hash, "invalid_key") # => false
        def string_or_symbol_key?(hash, key)
          hash.key?(key.to_s) || hash.key?(key.to_sym)
        end

        # Fetch the value from the hash using the key in string or symbol format
        # @param hash [Hash] the hash to fetch the value from
        # @param key [String, Symbol] the key to fetch the value for
        # @return [Object] the value associated with the key
        # @example
        #   hash = { "key" => "value" }
        #   fetch_with_string_or_symbol_key(hash, "key") # => "value"
        #   fetch_with_string_or_symbol_key(hash, :key) # => "value"
        #   fetch_with_string_or_symbol_key(hash, "invalid_key") # => nil
        def fetch_with_string_or_symbol_key(hash, key)
          if hash.key?(key.to_s)
            hash[key.to_s]
          elsif hash.key?(key.to_sym)
            hash[key.to_sym]
          end
        end

        def add_method_if_not_defined(klass, method_name, &block)
          unless klass.method_defined?(method_name)
            klass.class_eval do
              define_method(method_name, &block)
            end
          end
        end

        def add_accessor_if_not_defined(klass, attribute)
          add_getter_if_not_defined(klass, attribute)
          add_setter_if_not_defined(klass, attribute)
        end

        def add_boolean_accessor_if_not_defined(klass, attribute)
          add_boolean_getter_if_not_defined(klass, attribute)
          add_setter_if_not_defined(klass, attribute)
        end

        def add_getter_if_not_defined(klass, attribute)
          add_method_if_not_defined(klass, attribute) do
            instance_variable_get(:"@__#{attribute}")
          end
        end

        def add_boolean_getter_if_not_defined(klass, attribute)
          add_method_if_not_defined(klass, "#{attribute}?") do
            !!instance_variable_get(:"@__#{attribute}")
          end
        end

        def add_setter_if_not_defined(klass, attribute)
          add_method_if_not_defined(klass, "#{attribute}=") do |value|
            instance_variable_set(:"@__#{attribute}", value)
          end
        end

        def deep_dup(object)
          return object if object.nil?

          case object
          when Hash then deep_dup_hash(object)
          when Array then deep_dup_array(object)
          else deep_dup_object(object)
          end
        end

        private

        def deep_dup_hash(hash)
          hash.transform_values { |value| deep_dup(value) }
        end

        def deep_dup_array(array)
          array.map { |value| deep_dup(value) }
        end

        def deep_dup_object(object)
          object.respond_to?(:deep_dup) ? object.deep_dup : object.dup
        end

        def camelize_part(part)
          part.gsub(/(?:_|-|^)([a-z\d])/i) { $1.upcase }
        end
      end
    end
  end
end
