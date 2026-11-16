# frozen_string_literal: true

module Lutaml
  module Model
    class SerializationAdapter
      def self.handles_format(format)
        @handles = format
      end

      def self.document_class(klass = nil)
        if klass
          @document_class = klass
        else
          @document_class
        end
      end

      def self.parse(data, _options = {})
        document_class.parse(data)
      end
    end
  end
end
