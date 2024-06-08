# lib/lutaml/model/mapping_rule.rb
module Lutaml
  module Model
    class MappingRule
      attr_reader :name, :to, :render_nil, :custom_methods, :delegate

      def initialize(name, to:, render_nil: false, with: {}, delegate: nil)
        @name = name
        @to = to
        @render_nil = render_nil
        @custom_methods = with
        @delegate = delegate
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
    end
  end
end
