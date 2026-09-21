# frozen_string_literal: true

module DeferHost
  class NeverLoadedModel < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      element "never"
      map_element "value", to: :value
    end
  end
end
