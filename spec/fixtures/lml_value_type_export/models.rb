# frozen_string_literal: true

require "lutaml/model"

# Named custom value types and models for lml_value_type_export_spec.
# SlugType/CountType stand in for consumer types such as unitsml's
# XmlIdType: a Type::Value subclass the exporter cannot know the meaning of.
module LmlValueTypeExportFixtures
  class SlugType < Lutaml::Model::Type::Value
    def self.cast(value)
      value&.to_s
    end
  end

  class CountType < Lutaml::Model::Type::Value
    def self.cast(value)
      value.nil? ? nil : Integer(value)
    end
  end

  class AmountType < Lutaml::Model::Type::Value
    def self.cast(value)
      value&.to_s
    end
  end

  class OtherSlugType < SlugType; end

  class Account < Lutaml::Model::Serializable
    attribute :slug, SlugType, default: -> { "x" }.call
    attribute :tags, SlugType, collection: true
    attribute :limit, CountType, default: 7
    attribute :label, :string

    xml do
      root "account"
      map_attribute "slug", to: :slug
      map_element "tag", to: :tags
      map_element "limit", to: :limit
      map_element "label", to: :label
    end

    json do
      map "slug", to: :slug
      map "tags", to: :tags
      map "limit", to: :limit
      map "label", to: :label
    end
  end

  class Ledger < Lutaml::Model::Serializable
    attribute :owner, Account
    attribute :code, SlugType

    json do
      map "owner", to: :owner
      map "code", to: :code
    end
  end

  class Plain < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :count, :integer, default: 3

    json do
      map "name", to: :name
      map "count", to: :count
    end
  end

  class ProcDefault < Lutaml::Model::Serializable
    attribute :slug, SlugType, default: -> { "generated" }

    json do
      map "slug", to: :slug
    end
  end

  class Subclassed < Lutaml::Model::Serializable
    attribute :slug, OtherSlugType

    json do
      map "slug", to: :slug
    end
  end

  class BadDefault < Lutaml::Model::Serializable
    attribute :limit, CountType, default: "seven"

    json do
      map "limit", to: :limit
    end
  end

  class Priced < Lutaml::Model::Serializable
    attribute :amount, AmountType, default: "9.50"

    json do
      map "amount", to: :amount
    end
  end
end
