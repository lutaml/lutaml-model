# frozen_string_literal: true

require "singleton"

module Lutaml
  module Model
    class UninitializedClass
      include Singleton

      def to_s
        self
      end

      def inspect
        "uninitialized"
      end

      def uninitialized?
        true
      end

      def match?(_args)
        false
      end

      def include?(_args)
        false
      end

      def gsub(_, _)
        self
      end

      def to_yaml
        nil
      end

      def to_f
        self
      end

      def size
        0
      end

      def encoding
        # same as default encoding for string
        "".encoding
      end

      def method_missing(method, *_args, &)
        if method.end_with?("?")
          false
        end
      end

      def respond_to_missing?(_method_name, _include_private = false)
        true
      end
    end
  end
end
