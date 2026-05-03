# frozen_string_literal: true

module Lutaml
  module Model
    # Thread-local scoped adapter override stack.
    #
    # Provides block-scoped adapter overrides for testing and library stacking.
    # Each thread has its own stack — no mutex needed.
    #
    # @example Testing with a specific adapter
    #   Lutaml::Model::Config.with_adapter(xml: :ox) do
    #     MyClass.from_xml(xml)  # Uses Ox
    #   end
    #   # Outside the block, reverts to configured default
    #
    # @example Library stacking
    #   # Library A guarantees Ox internally
    #   def self.parse(data)
    #     Config.with_adapter(xml: :nokogiri) { MyModel.from_xml(data) }
    #   end
    #
    class AdapterScope
      STACK_KEY = :__lutaml_adapter_scope_stack
      EMPTY = {}.freeze

      # Push adapter overrides and yield. Restores previous scope on exit.
      #
      # @param overrides [Hash{Symbol => Symbol}] format => adapter type name
      #   e.g., { xml: :ox, json: :oj }
      # @yield block within which overrides are active
      # @return [Object] the block's return value
      def self.with(overrides)
        stack = Thread.current[STACK_KEY] ||= []
        stack.push(overrides)
        yield
      ensure
        stack.pop
        Thread.current[STACK_KEY] = nil if stack.empty?
      end

      # Return the current scope's overrides hash.
      #
      # @return [Hash{Symbol => Symbol}] current overrides or empty hash
      def self.current
        Thread.current[STACK_KEY]&.last || EMPTY
      end

      # Return the override for a specific format from the current scope.
      #
      # @param format [Symbol] the format name (:xml, :json, etc.)
      # @return [Symbol, nil] the adapter type name or nil
      def self.override_for(format)
        current[format]
      end

      # Clear all scope state (for testing reset).
      #
      # @return [void]
      def self.reset!
        Thread.current[STACK_KEY] = nil
      end
    end
  end
end
