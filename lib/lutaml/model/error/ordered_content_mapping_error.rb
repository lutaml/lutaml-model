# frozen_string_literal: true

module Lutaml
  module Model
    class OrderedContentMappingError < Error
      def initialize(model_class)
        @model_class = model_class
        super()
      end

      def to_s
        "Element-only content model (`ordered`) does not support `map_content` in #{@model_class}. " \
          "Use `mixed_content` instead of `ordered` when you need to capture text content between elements."
      end
    end
  end
end
