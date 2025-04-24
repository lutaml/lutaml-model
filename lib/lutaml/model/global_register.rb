# frozen_string_literal: true

module Lutaml
  module Model
    class GlobalRegister
      include Singleton
      attr_writer :registers

      def initialize
        @registers = {}
      end

      def register(register)
        @registers[register.id] = register
      end

      def self.register(register)
        instance.register(register)
      end

      def self.lookup(id)
        instance.lookup(id)
      end

      def lookup(id)
        @registers[id.to_sym]
      end

      def register_objects
        @registers.values
      end
    end
  end
end
