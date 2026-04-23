# frozen_string_literal: true

require_relative "base"

module Lutaml
  module Xml
    module Builder
      class Ox < Base
        def self.moxml_backend
          :ox
        end
      end
    end
  end
end
