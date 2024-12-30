# frozen_string_literal: true

module Lutaml
  module Model
    module XmlAdapter
      module Oga
        class Document < ::Oga::XML::Document
          def initialize(options = {})
            super
          end

          def text(value = nil)
            children << ::Oga::XML::Text.new(text: value)
            self
          end

          def method_missing(method_name, *args)
            @builder.public_send(method_name, *args)
          end

          def respond_to_missing?(method_name, include_private = false)
            @builder.respond_to?(method_name) || super
          end
        end
      end
    end
  end
end
