# frozen_string_literal: true

module Lutaml
  module Model
    class DispatchBlock < ConsolidationRule
      attr_reader :discriminator, :routes

      # @param discriminator [Symbol] attribute name to discriminate by
      # @param routes [Hash{String => Symbol}] value -> target attribute
      def initialize(discriminator, routes)
        super
        @discriminator = discriminator
        @routes = routes
      end

      def route_for(value)
        @routes[value]
      end
    end

    # Helper builder for the dispatch_by block
    class DispatchBuilder
      def evaluate(&)
        @routes = {}
        instance_eval(&)
        @routes
      end

      def route(mapping)
        @routes.merge!(mapping)
      end
    end
  end
end
