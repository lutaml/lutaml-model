module Lutaml
  module Model
    class NoRootNamespaceError < Error
      def to_s
        "Cannot assign namespace to `no_root`"
      end
    end
  end
end
