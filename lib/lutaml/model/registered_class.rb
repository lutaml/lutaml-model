# frozen_string_literal: true

module Lutaml
  module Model
    class RegisteredClass
      attr_accessor :register, :klass

      def initialize(register, klass)
        @register = register
        @klass = klass
      end

      def new(*args)
        klass.new(*args, { register: register })
      end

      def to_s
        "RegisteredClass: #{@name}, Attributes: #{@attributes}"
      end
    end
  end
end
