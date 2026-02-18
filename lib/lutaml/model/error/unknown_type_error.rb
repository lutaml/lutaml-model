module Lutaml
  module Model
    class UnknownTypeError < Error
      attr_reader :type_name, :context_id, :available_types

      # Create a new UnknownTypeError.
      #
      # @param type_name [Symbol, String] The name of the unknown type
      # @param context_id [Symbol, nil] Optional context ID where type was looked up
      # @param available_types [Array<Symbol>, nil] Optional list of available types
      def initialize(type_name, context_id: nil, available_types: nil)
        @type_name = type_name
        @context_id = context_id
        @available_types = available_types

        message = build_message
        super(message)
      end

      private

      def build_message
        msg = "Unknown type '#{@type_name}'"
        msg += " in context '#{@context_id}'" if @context_id
        if @available_types && !@available_types.empty?
          msg += ". Available types: #{@available_types.join(', ')}"
        end
        msg
      end
    end
  end
end
