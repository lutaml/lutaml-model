module Lutaml
  module Model
    class RuleValueExtractor < Services::Base
      # Memoized per rule object: the extractor is fresh per node, so
      # the name array rebuilt per node is pure churn (~145k
      # allocations per heroku.json parse). Rules are stable per
      # (class, register); the bounded cache tracks their arrays.
      RULE_NAMES_CACHE = if Lutaml::Model.opal?
                           {}
                         else
                           Lutaml::Model::RuntimeCompatibility
                             .require_native("concurrent")
                           Concurrent::Map.new
                         end

      # The extractor is pure stateless logic over its arguments; the
      # per-call `new(*args).call` instance (Services::Base's default)
      # allocated an object plus seven ivar writes per rule per element
      # (~24k objects per 60 glossarist documents). The class-level call
      # runs the same walk without the throwaway instance. The instance
      # API is kept for compatibility.
      def self.call(rule, doc, format, attr, register, _options,
instance_object)
        rule_names = RULE_NAMES_CACHE[rule] ||=
          rule.multiple_mappings? ? rule.name : [rule.name]

        rule_names.each do |rule_name|
          value = rule_value_for(rule, doc, format, attr, register,
                                 instance_object, rule_name)
          return value if Utils.initialized?(value)
        end

        Lutaml::Model::UninitializedClass.instance
      end

      def self.rule_value_for(rule, doc, format, attr, register,
instance_object, name)
        # When name is nil but document is a hash-like object with a single key matching
        # the attribute name, extract that value. This handles the case where
        # map to: :content is used and the document is {"content": "value"}
        # Note: doc may be an Oj-generated Hash which is_a?(Hash) returns false for,
        # so we use respond_to? for the hash-like protocol check.
        if name.nil? && doc.respond_to?(:key?) && doc.respond_to?(:values) && doc.size == 1
          attr_name = rule.to
          if doc.key?(attr_name.to_s) || doc.key?(attr_name.to_sym)
            return doc.values.first
          end
        end

        return doc if name.nil? || rule.root_mapping?
        return convert_to_format(doc, format) if rule.raw_mapping?
        return Utils.fetch_str_or_sym(doc, name) if Utils.string_or_symbol_key?(doc, name)

        if attr
          resolved = attr.default_value(register, instance_object)
          return resolved unless Utils.uninitialized?(resolved)
        end

        Lutaml::Model::UninitializedClass.instance
      end

      def self.convert_to_format(doc, format)
        adapter = Lutaml::Model::Config.adapter_for(format)
        adapter.new(doc).public_send(:"to_#{format}")
      end

      def initialize(rule, doc, format, attr, register, options,
instance_object)
        super()

        @rule = rule
        @doc = doc
        @format = format
        @attr = attr
        @register = register
        @options = options
        @instance_object = instance_object
      end

      attr_reader :rule, :doc, :format, :attr, :register, :options,
                  :instance_object

      def call
        self.class.call(rule, doc, format, attr, register, options,
                        instance_object)
      end

      private

      def uninitialized_value
        Lutaml::Model::UninitializedClass.instance
      end
    end
  end
end
