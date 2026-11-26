# frozen_string_literal: true

module Lutaml
  module Lml
    # RS 3010 extension: a serialization mapping declared separately from
    # its class and linked by target name —
    #   mapping xml Ceramic { element "ceramic" … }
    class SerializationMapping < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      attribute :format, :string
      attribute :target, :string
      attribute :element_name, :string
      attribute :namespace_ref, :string
      attribute :mixed_content, :boolean, default: false
      attribute :rules, 'Lutaml::Lml::MappingRule', collection: true, default: -> { [] }
    end
  end
end
