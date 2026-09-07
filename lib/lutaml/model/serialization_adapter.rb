# frozen_string_literal: true

module Lutaml
  module Model
    class SerializationAdapter
      def self.handles_format(format)
        # Lutaml::Model::Config.register_format(format, self)
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
        # Keep the two-argument call shape: downstream custom adapters may
        # define .parse(data, options) with a required second parameter.
        document_class.parse(data, {})
      end
    end
  end
end
