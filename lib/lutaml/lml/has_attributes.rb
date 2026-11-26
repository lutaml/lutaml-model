# frozen_string_literal: true

module Lutaml
  module Lml
    module HasAttributes
      def update_attributes(attributes = {})
        attributes.to_h.each do |name, value|
          value = value.to_s if value.is_a?(Parsanol::Slice)
          public_send(:"#{name}=", value)
        end
      end
    end
  end
end
