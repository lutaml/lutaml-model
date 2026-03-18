# frozen_string_literal: true

module Lutaml
  module Jsonl
    module Adapter
      class Document
        def initialize(jsons = [], register: nil)
          @jsons = jsons
          @register = register || Lutaml::Model::Config.default_register
        end
      end
    end
  end
end
