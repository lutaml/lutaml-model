# frozen_string_literal: true

module Lutaml
  module Lml
    # RS 3001 par. Value type: a reference to another instance
    # (`reference:(path)` / `ref:(path)`). The attribute's value slot keeps
    # its primitive wire shape (a `reference` hash); this is the typed
    # domain view of it, built at one canonical point
    # (TopElementAttribute#reference) so validation and serialization
    # consume structured references instead of re-sniffing hashes.
    class Reference < Lutaml::Model::Serializable
      attribute :path, :string

      def segments
        @segments ||= path.to_s.split('.')
      end

      def to_s
        path.to_s
      end
    end
  end
end
