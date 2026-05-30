# frozen_string_literal: true

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
