# frozen_string_literal: true

require_relative "base"

module Lutaml
  module Xml
    module Builder
      class Rexml < Base
        def self.moxml_backend
          :rexml
        end
      end
    end
  end
end
