module Lutaml
  module Xml
      class Element
      include Lutaml::Model::Liquefiable

      attr_reader :type, :name, :text_content

      def initialize(type, name, text_content: nil)
      @type = type
      @name = name
      # For text nodes, store both marker ("text") and actual content
      @text_content = text_content || name
      end

      def text?
      @type == "Text" && @name != "#cdata-section"
      end

      def element_tag
      @name unless text?
      end

      def eql?(other)
      return false unless other.is_a?(self.class)

      # Only compare type and name for backward compatibility
      # text_content is for internal round-trip use only
      @type == other.type && @name == other.name
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
      %i[text? element_tag type name text_content].each do |attr_name|
        self.class.register_drop_method(attr_name)
      end

      self.class.drop_class.define_method(:==) do |other|
        return false unless other.is_a?(self.class)

        # Only compare type and name for backward compatibility
        __getobj__.type == other.__getobj__.type && __getobj__.name == other.__getobj__.name
      end
      end
      end
  end
end
