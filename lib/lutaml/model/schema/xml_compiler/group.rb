# frozen_string_literal: true

require_relative "utility"

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Group
          include Utility

          def initialize(group)
            @group = group
          end
        end
      end
    end
  end
end
