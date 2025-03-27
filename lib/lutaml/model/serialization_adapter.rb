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
        document_class.parse(data, create_additions: false)
      end
    end
  end
end
