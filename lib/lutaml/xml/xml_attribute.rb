# frozen_string_literal: true

module Lutaml
  module Xml
    # Represents an XML attribute
    class XmlAttribute
      attr_reader :name, :value, :namespace, :namespace_prefix

      def initialize(name, value, namespace: nil, namespace_prefix: nil)
        @name = name
        @value = value
        @namespace = namespace
        @namespace_prefix = namespace_prefix
      end

      # Memoized: name/namespace/prefix are fixed at construction, and
      # these spellings are probed per element per rule during a parse
      # (5M+ substring mints on a 2M-node document before the memo).
      def unprefixed_name
        @unprefixed_name ||= if namespace_prefix
                               name[((name.rindex(":") || -1) + 1)..]
                             else
                               name
                             end
      end

      def namespaced_name
        # For type-namespaced attributes (those with xml_namespace declaration),
        # return the prefixed name (e.g., "xml:lang", "ex:attr")
        # rather than URI:name format (e.g., "http://www.w3.org/XML/1998/namespace:lang")
        @namespaced_name ||= if namespace_prefix
                               name
                             elsif namespace
                               "#{namespace}:#{unprefixed_name}"
                             else
                               unprefixed_name
                             end
      end

      # The local-name spellings this attribute can match under (its
      # unprefixed form and its split-local form when prefixed). Probed
      # per candidate per rule in the parse session; static per
      # attribute instance, so it is computed once here. Unprefixed
      # attributes (the common case) take the single-spelling fast
      # path: one Array, no substrings.
      def local_names
        @local_names ||= begin
          colon = name.rindex(":")
          if colon
            [unprefixed_name, name[(colon + 1)..]].uniq
          else
            [name]
          end
        end
      end
    end
  end
end
