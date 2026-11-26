# frozen_string_literal: true

module Lutaml
  module Lml
    # An instance with attribute assignments.
    class Instance < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      attribute :name, :string
      attribute :type, :string
      attribute :isa, :string
      attribute :attributes, "Lutaml::Lml::TopElementAttribute", collection: true
      attribute :instance, "Lutaml::Lml::Instance"
      attribute :template, "Lutaml::Lml::TopElementAttribute", collection: true
      attribute :parent, :string

      def each_attribute
        return enum_for(:each_attribute) unless block_given?

        Array(attributes).each do |attr|
          yield attr.name, attr.value, Array(attr.instances)
        end
      end
    end
  end
end
