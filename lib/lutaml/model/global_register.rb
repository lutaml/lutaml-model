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

      def lookup(id)
        @registers[id.to_sym]
      end

      def registered_objects
        @registers.values
      end

      class << self
        def register(register)
          instance.register(register)
        end

        def lookup(id)
          instance.lookup(id)
        end

        def registered_objects
          instance.registered_objects
        end
      end
    end
  end
end
