module Lutaml
  module Model
    module Xml
      class Element
        TEXT_TYPE = "Text".freeze
        ENTITY_MARKER = "__entity".freeze

        include Lutaml::Model::Liquefiable

        attr_reader :type, :name

        def initialize(type, name)
          @type = type
          @name = name
        end

        def text?
          @type == TEXT_TYPE &&
            @name != "#cdata-section" &&
            @name != ENTITY_MARKER
        end

        # Checks if this element represents an XML entity reference
        # @return [Boolean] true if this is an entity node, false otherwise
        def entity?
          @type == TEXT_TYPE &&
            @name == ENTITY_MARKER
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

        def to_liquid
          self.class.validate_liquid!
          self.class.register_liquid_drop_class unless self.class.drop_class

          register_liquid_methods
          self.class.drop_class.new(self)
        end

        alias == eql?

        private

        def register_liquid_methods
          %i[text? entity? element_tag type name].each do |attr_name|
            self.class.register_drop_method(attr_name)
          end

          self.class.drop_class.define_method(:==) do |other|
            return false unless other.is_a?(self.class)

            instance_variables.all? do |var|
              instance_variable_get(var) == other.instance_variable_get(var)
            end
          end
        end
      end
    end
  end
end
