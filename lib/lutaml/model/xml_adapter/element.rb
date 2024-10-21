module Lutaml
  module Model
    module XmlAdapter
      class Element
        attr_reader :type, :name

        def initialize(type, name)
          @type = type
          @name = name
        end

        def text?
          @type == "Text" && @name != "#cdata-section"
        end

        def element_tag
          @name unless text?
        end

        def eql?(other)
          return false unless other.is_a?(self.class)

          instance_variables.all? do |var|
            instance_variable_get(var) == other.instance_variable_get(var)
          end
        end

        alias == eql?
      end
    end
  end
end
