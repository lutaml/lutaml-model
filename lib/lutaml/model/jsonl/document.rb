# frozen_string_literal: true

module Lutaml
  module Model
    module Jsonl
      class Document
        def initialize(jsons = [], register: nil)
          @jsons = jsons
          @__register = register || Lutaml::Model::Config.default_register
        end
      end
    end
  end
end
