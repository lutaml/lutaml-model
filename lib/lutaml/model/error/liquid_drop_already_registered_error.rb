# frozen_string_literal: true

module Lutaml
  module Model
    class LiquidDropAlreadyRegisteredError < Error
      def initialize(drop_class_name)
        super("Liquid drop class '#{drop_class_name}' is already registered.")
      end
    end
  end
end
