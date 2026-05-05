# frozen_string_literal: true

module Lutaml
  module Model
    module Validation
      class RemediationResult < Lutaml::Model::Serializable
        attribute :success, :boolean
        attribute :message, :string
        attribute :fixed_codes, :string, collection: true

        json do
          map "success", to: :success
          map "message", to: :message
          map "fixed_codes", to: :fixed_codes
        end
      end
    end
  end
end
