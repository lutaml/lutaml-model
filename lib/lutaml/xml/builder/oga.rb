# frozen_string_literal: true

require_relative "base"

module Lutaml
  module Xml
    module Builder
      class Oga < Base
        def self.moxml_backend
          :oga
        end
      end
    end
  end
end
