module Lutaml
  module Model
    class MixedContentCollectionError < Error
      def initialize(attr_name, model_class)
        @attr_name = attr_name
        @model_class = model_class

        super()
      end

      def to_s
        "Mixed content requires `#{@attr_name}` to be a string collection in #{@model_class}. " \
          "Use `attribute :#{@attr_name}, :string, collection: true` when `mixed_content` is enabled."
      end
    end
  end
end
