require_relative "base"

module Lutaml
  module Model
    class ValidationRule
      attr_reader :attribute, :options, :custom_method

      def initialize(attribute: nil, custom_method: nil, options: {})
        if Utils.blank?(attribute) && Utils.blank?(custom_method)
          raise ArgumentError, "Missing attribute or custom method"
        end

        @attribute = attribute
        @options = options
        @custom_method = custom_method
      end

      def custom?
        Utils.present?(custom_method)
      end

      def has_options?
        options.is_a?(Hash)
      end
    end

    class Validator < Services::Base
      attr_reader :value, :validations, :errors, :memoization_container

      def initialize(value, validations, memoization_container)
        super()

        @errors = Errors.new
        @value = value
        @memoization_container = memoization_container

        resolve_validations(validations)
      end

      def call
        return [] if Utils.blank?(validations)

        @validations.each do |validation|
          if validation.custom?
            public_send(validation.custom_method, value)
          else
            validation.options.each do |key, rule|
              send(:"validate_#{key}", value, validation.attribute, rule)
            end
          end
        end

        errors.messages
      end

      private

      def resolve_validations(validations_block)
        @validations ||= []
        return unless validations_block

        instance_eval(&validations_block)
      end

      def validate(method_name)
        @validations << ValidationRule.new(custom_method: method_name)
      end

      def validates(attribute, options)
        @validations << ValidationRule.new(attribute: attribute, options: options)
      end

      def validate_presence(model, attr, rule)
        return if rule.nil?

        if model.is_a?(Array)
          model.each { |v| validate_presence(v, attr, rule) }
          return
        end

        value = model.public_send(attr)
        return if Utils.present?(value)

        errors.add(attr, "`#{attr}` is required")
      end

      def validate_numericality(model, attr, rule)
        return if rule.nil?

        if model.is_a?(Array)
          model.each { |v| validate_numericality(v, attr, rule) }
          return
        end

        value = model.public_send(attr)
        return unless validate_integer(attr, value)

        validate_comparison_rules(attr, value, rule)
      end

      def validate_integer(attr, value)
        return true if value.is_a?(Integer)

        errors.add(attr, "`#{attr}` value is `#{value.class}`, but expected integer")
        false
      end

      def validate_comparison_rules(attr, value, options)
        validate_less_than(attr, value, options[:less_than])
        validate_greater_than(attr, value, options[:greater_than])
        validate_equal_to(attr, value, options[:equal_to])
      end

      def validate_less_than(attr, value, limit)
        return if !limit || value < limit

        errors.add(attr, "#{attr} value is `#{value}`, which is not less than #{limit}")
      end

      def validate_greater_than(attr, value, limit)
        return if !limit || value > limit

        errors.add(attr, "#{attr} value is `#{value}`, which is not greater than #{limit}")
      end

      def validate_equal_to(attr, value, target)
        return if !target || value == target

        errors.add(attr, "#{attr} value is `#{value}`, which is not equal to #{target}")
      end
    end
  end
end
