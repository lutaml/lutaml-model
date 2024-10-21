module Lutaml
  module Model
    class GroupAttribute
      attr_reader :attributes

      def initialize
        @attributes = {}
        @group = "group_#{hash}"
      end

      def attribute(name, type, options = {})
        options[:group] = @group
        attributes[name] = [type, options]
      end
    end
  end
end
