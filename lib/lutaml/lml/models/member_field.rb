# frozen_string_literal: true

module Lutaml
  module Lml
    # A typed payload field declared on an enum:
    #   member_fields { abbreviation String  urn_segment String }
    class MemberField < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      attribute :name, :string
      attribute :type, :string
    end
  end
end
