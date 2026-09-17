# frozen_string_literal: true

module Lutaml
  module Xml
    module Builder
      class Nokogiri < Base
        def self.moxml_backend
          :nokogiri
        end
      end
    end
  end
end
