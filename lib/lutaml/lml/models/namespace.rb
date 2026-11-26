# frozen_string_literal: true

module Lutaml
  module Lml
    # RS 3010 extension: a declared XML namespace (uri + optional prefix).
    # The compiler generates the corresponding Lutaml::Model::XmlNamespace
    # subclass for the compiled model namespace.
    class Namespace < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      attribute :name, :string
      attribute :uri, :string
      attribute :prefix, :string
    end
  end
end
