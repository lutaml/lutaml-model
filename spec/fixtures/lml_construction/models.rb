# frozen_string_literal: true

require "lutaml/model"

# Models with and without hand-written application construction, for
# lml_construction_spec. The side-effect log (ran) proves bodies never run.
module LmlConstructionFixtures
  def self.ran
    @ran ||= []
  end

  class Money < Lutaml::Model::Serializable
    attribute :amount, :integer
    attribute :currency, :string

    json do
      map "amount", to: :amount
      map "currency", to: :currency
    end

    def initialize(attrs = {})
      LmlConstructionFixtures.ran << :money
      super
    end
  end

  class Euro < Money; end

  module Audited
    def initialize(*)
      LmlConstructionFixtures.ran << :audited
      super
    end
  end

  class Ledger < Lutaml::Model::Serializable
    include Audited

    attribute :note, :string

    json do
      map "note", to: :note
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

  class Holder < Lutaml::Model::Serializable
    attribute :money, Money
    attribute :plain, Plain

    json do
      map "money", to: :money
      map "plain", to: :plain
    end
  end
end
