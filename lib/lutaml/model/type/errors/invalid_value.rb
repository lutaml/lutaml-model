# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      module Errors
        class InvalidValue < Lutaml::Model::Error
          def initialize(message)
            @message = message

            super()
          end

          def to_s
            @message
          end
        end
      end
    end
  end
end
