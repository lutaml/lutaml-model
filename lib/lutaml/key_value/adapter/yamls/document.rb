# frozen_string_literal: true

module Lutaml
  module KeyValue
    module Adapter
      module Yamls
        class Document
          def initialize(yamls = [], register: nil)
            @yamls = yamls
            @register = register || Lutaml::Model::Config.default_register
          end
        end
      end
    end
  end
end
