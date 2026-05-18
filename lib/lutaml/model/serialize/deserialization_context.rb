# frozen_string_literal: true

module Lutaml
  module Model
    module Serialize
      # Encapsulates the parent-to-child options propagation contract.
      #
      # During deserialization, a parent passes context to its children via an
      # options Hash. Only certain keys are safe to propagate — parent-internal
      # keys (resolved_type, namespace_uri, converted) must be stripped so
      # children derive their own context.
      #
      # This class is the single source of truth for which keys propagate,
      # replacing scattered CHILD_PROPAGATION_KEYS constants and ad-hoc
      # `.slice` calls.
      #
      # Usage:
      #   child_options = DeserializationContext.propagate(options).merge(register: register)
      #   klass.apply_mappings(value, format, child_options)
      class DeserializationContext
        # Keys that are safe to propagate from parent to child deserialization.
        #
        # Parent-internal keys (namespace_uri, resolved_type, converted, mappings)
        # are intentionally excluded — children must derive their own context.
        PROPAGATION_KEYS = %i[
          lutaml_parent
          lutaml_root
          default_namespace
          import_declaration_plan
          polymorphic
          collection
          render_empty
          render_nil
          cdata
        ].freeze

        # Extract propagable keys from a parent options hash.
        #
        # Returns a new Hash containing only the keys safe for child
        # deserialization. Parent-internal keys are excluded.
        #
        # @param options [Hash] The parent's options hash
        # @return [Hash] A new hash with only propagable keys
        def self.propagate(options)
          options.slice(*PROPAGATION_KEYS)
        end
      end
    end
  end
end
