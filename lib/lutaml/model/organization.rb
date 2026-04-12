# frozen_string_literal: true

module Lutaml
  module Model
    # Stores the format-agnostic declaration that a Collection
    # produces organized instances of a GroupClass.
    #
    # Created by Collection.organizes(:name, GroupClass).
    # Stored as class-level metadata on the Collection subclass.
    #
    # @example
    #   class TitleCollection < Lutaml::Model::Collection
    #     organizes :per_lang, PerLangTitleGroup
    #   end
    #
    #   TitleCollection.organization
    #   #=> #<Organization @name=:per_lang, @group_class=PerLangTitleGroup>
    class Organization
      attr_reader :name, :group_class

      # @param name [Symbol] attribute name on the Collection
      # @param group_class [Class] the GroupClass type
      def initialize(name, group_class)
        @name = name
        @group_class = group_class
      end
    end
  end
end
