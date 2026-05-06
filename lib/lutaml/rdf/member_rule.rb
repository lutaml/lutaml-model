# frozen_string_literal: true

module Lutaml
  module Rdf
    class MemberRule
      attr_reader :attr_name

      def initialize(attr_name)
        @attr_name = attr_name.to_sym
      end
    end
  end
end
