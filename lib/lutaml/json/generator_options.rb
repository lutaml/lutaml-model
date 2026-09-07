# frozen_string_literal: true

require "json"

module Lutaml
  module Json
    # Filters the options LutaML threads through serialization down to the
    # subset the JSON generator accepts.
    #
    # json 2.x silently ignored unknown generator options; json 3.0 raises
    # ArgumentError on them, so LutaML's own options (:register, :pretty and
    # any caller-supplied extras) have to be stripped before they reach
    # JSON.generate.
    module GeneratorOptions
      # Options the generator accepts on both json 2.x and 3.x. Measured
      # against 2.9.1, 2.15.2, 2.19.9, 2.20.0, 2.21.1, 2.21.2 and 3.0.0.
      # :escape_slash is NOT here because json 3.0 removed it; on 2.x it still
      # arrives via DERIVED_PERMITTED. :allow_duplicate_key IS here because the
      # generator accepts it on every version while JSON::State never exposed
      # it as an accessor, so the derived half alone would miss it.
      BASE_PERMITTED = %i[
        allow_duplicate_key allow_nan array_nl as_json ascii_only
        buffer_initial_length depth indent max_nesting object_nl script_safe
        sort_keys space space_before strict
      ].freeze

      # Additive, so a json release that adds an option needs no change here.
      # Opal's JSON shim has no State class, hence the guard.
      DERIVED_PERMITTED =
        if defined?(::JSON::State)
          accessors = ::JSON::State.instance_methods(false).grep(/\A[a-z_][a-z0-9_]*=\z/)
          accessors.map { |name| name.to_s.chomp("=").to_sym }
        else
          []
        end.freeze

      PERMITTED = (BASE_PERMITTED | DERIVED_PERMITTED).freeze

      # LutaML's own options, which no JSON engine understands. The stdlib
      # generator gets an ALLOWLIST because json 3.0 raises on anything it does
      # not know. MultiJson gets this DENYLIST instead: its accepted options
      # depend on the backend (Oj takes :omit_nil, Yajl takes others), so an
      # allowlist built from JSON::State would silently drop them.
      INTERNAL = %i[
        register adapter _adapter_override _generator_state
        collection from_collection
      ].freeze

      def self.strip_internal(options)
        return {} unless options.is_a?(::Hash)

        options.except(*INTERNAL)
      end

      # json 3.0 removed :escape_slash, which was only ever an alias of
      # :script_safe. Dropping it would silently stop escaping slashes, so it
      # is translated instead of discarded.
      RENAMED = { escape_slash: :script_safe }.freeze

      def self.filter(options)
        return {} unless options.is_a?(::Hash)

        options.each_with_object({}) do |(key, value), kept|
          key = RENAMED.fetch(key, key) unless PERMITTED.include?(key)
          kept[key] = value if PERMITTED.include?(key)
        end
      end

      # Ruby's JSON generator calls #to_json with a JSON::State whenever a
      # document is nested inside another JSON.generate call. That is the
      # generator's own state, not a LutaML options hash, and json 3.0 removed
      # JSON::State#[], so it must never be read like one.
      def self.lutaml_options?(argument)
        argument.nil? || argument.is_a?(::Hash)
      end
    end
  end
end
