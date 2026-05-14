# frozen_string_literal: true

module Lutaml
  module Model
    # Protocol module for objects that support deep duplication.
    #
    # Include this module in any class that needs custom deep-copy semantics
    # beyond Ruby's default `dup`. Used by Utils.deep_dup to dispatch correctly
    # via type checking instead of respond_to?.
    module DeepDupable
      def deep_dup
        raise NotImplementedError, "#{self.class} must implement deep_dup"
      end
    end
  end
end
