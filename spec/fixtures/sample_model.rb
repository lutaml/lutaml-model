require "lutaml/model"

class SampleModelTag < Lutaml::Model::Serializable
  attribute :text, :string, default: -> { "" }

  xml do
    root "Tag"
    map_content to: :text
  end
end

class SampleModel < Lutaml::Model::Serializable
  attribute :name, :string, default: -> { "Anonymous" }
  attribute :age, :integer, default: -> { 18 }
  attribute :balance, :decimal, default: -> { BigDecimal("0.0") }
  attribute :tags, SampleModelTag, collection: true
  attribute :preferences, :hash, default: -> { { notifications: true } }
  attribute :uuid, :uuid, default: -> { SecureRandom.uuid }
  attribute :status, :symbol, default: -> { :active }
  attribute :large_number, :integer, default: -> { 0 }
  attribute :avatar, :binary, default: -> { "" }
  attribute :website, :url, default: -> { URI.parse("http://example.com") }
  attribute :email, :string, default: -> { "example@example.com" }
  attribute :ip_address, :ip_address, default: -> { IPAddr.new("127.0.0.1") }
  attribute :metadata, :json, default: -> { "{}" }
  attribute :role, :string, values: %w[user admin guest], default: -> { "user" }

  xml do
    root "SampleModel"
    map_element "Name", to: :name
    map_element "Age", to: :age
    map_element "Balance", to: :balance
    map_element "Tags", to: :tags
    map_element "Preferences", to: :preferences
    map_element "Uuid", to: :uuid
    map_element "Status", to: :status
    map_element "LargeNumber", to: :large_number
    map_element "Avatar", to: :avatar
    map_element "Website", to: :website
    map_element "Email", to: :email
    map_element "IpAddress", to: :ip_address
    map_element "Metadata", to: :metadata
    map_element "Role", to: :role
  end

  yaml do
    map "name", to: :name
    map "age", to: :age
  end
end
