# frozen_string_literal: true

module Lutaml
  module Model
    class GlobalRegister
      include Singleton
      attr_writer :registers

      def initialize
        @registers = {}
      end

      def register(model_register)
        @registers[model_register.id] = model_register
      end

      def lookup(id)
        @registers[id.to_sym]
      end

      def registered_objects
        @registers.values
      end

      def self.register(model_register)
        instance.register(model_register)
      end

      def self.lookup(id)
        instance.lookup(id)
      end

      def self.registered_objects
        instance.registered_objects
      end
    end
  end
end
