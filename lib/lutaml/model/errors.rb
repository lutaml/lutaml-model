# frozen_string_literal: true

module Lutaml
  module Model
    class Errors
      include Enumerable

      def initialize
        @errors = {}
      end

      def add(attr, error)
        @errors[attr] ||= []
        @errors[attr] << error
      end

      def empty?
        @errors.empty?
      end

      def each(&)
        @errors.each(&)
      end

      def full_messages
        @errors.map { |attr, errors| "#{attr}: #{errors.join(', ')}" }
      end

      def messages
        @errors.map { |_, errors| errors.join(", ") }.flatten
      end

      def to_s
        full_messages.join("\n")
      end
    end
  end
end
