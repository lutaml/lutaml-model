# spec/fixtures/sample_model.rb
require "lutaml/model"

class SampleModel < Lutaml::Model::BaseModel
  attribute :name, Lutaml::Model::Type::String, default: -> { "Anonymous" }
  attribute :age, Lutaml::Model::Type::Integer, default: -> { 18 }
  attribute :balance, Lutaml::Model::Type::Decimal, default: -> { BigDecimal("0.0") }
  attribute :tags, Lutaml::Model::Type::Array, default: -> { [] }
  attribute :preferences, Lutaml::Model::Type::Hash, default: -> { { notifications: true } }
  attribute :uuid, Lutaml::Model::Type::UUID, default: -> { SecureRandom.uuid }
  attribute :status, Lutaml::Model::Type::Symbol, default: -> { :active }
  attribute :large_number, Lutaml::Model::Type::BigInteger, default: -> { 0 }
  attribute :avatar, Lutaml::Model::Type::Binary, default: -> { "" }
  attribute :website, Lutaml::Model::Type::URL, default: -> { URI.parse("http://example.com") }
  attribute :email, Lutaml::Model::Type::Email, default: -> { "example@example.com" }
  attribute :ip_address, Lutaml::Model::Type::IPAddress, default: -> { IPAddr.new("127.0.0.1") }
  attribute :metadata, Lutaml::Model::Type::JSON, default: -> { {} }
  attribute :role, Lutaml::Model::Type::Enum, options: %w[user admin guest], default: -> { "user" }

  xml do
    root "SampleModel"
    map_element "Name", to: :name
    map_element "Age", to: :age
    map_element "Balance", to: :balance
    map_element "Tags", to: :tags
    map_element "Preferences", to: :preferences
    map_element "UUID", to: :uuid
    map_element "Status", to: :status
    map_element "LargeNumber", to: :large_number
    map_element "Avatar", to: :avatar
    map_element "Website", to: :website
    map_element "Email", to: :email
    map_element "IPAddress", to: :ip_address
    map_element "Metadata", to: :metadata
    map_element "Role", to: :role
  end
end
