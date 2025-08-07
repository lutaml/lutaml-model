# frozen_string_literal: true

module Lutaml
  module Model
    module Yamls
      class Document
        def initialize(yamls = [], register: nil)
          @yamls = yamls
          @__register = register || Lutaml::Model::Config.default_register
        end
      end
    end
  end
end
