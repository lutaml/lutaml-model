module Lutaml
  module Model
    class MappingRule
      attr_reader :name,
                  :to,
                  :render_nil,
                  :custom_methods,
                  :delegate,
                  :mixed_content,
                  :child_mappings

      def initialize(
        name,
        to:,
        render_nil: false,
        with: {},
        delegate: nil,
        mixed_content: false,
        namespace_set: false,
        child_mappings: nil
      )
        @name = name
        @to = to
        @render_nil = render_nil
        @custom_methods = with
        @delegate = delegate
        @mixed_content = mixed_content
        @namespace_set = namespace_set
        @child_mappings = child_mappings
      end

      alias from name
      alias render_nil? render_nil

      def prefixed_name
        if prefix
          "#{prefix}:#{name}"
        else
          name
        end
      end

      def serialize(model, value)
        if custom_methods[:to]
          model.send(custom_methods[:to], model, value)
        else
          value
        end
      end

      def deserialize(model, doc)
        if custom_methods[:from]
          model.send(custom_methods[:from], model, doc)
        else
          doc[name.to_s]
        end
      end

      def namespace_set?
        @namespace_set
      end
    end
  end
end
