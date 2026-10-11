# frozen_string_literal: true

module Lutaml
  module Xml
    # The leptris plan fast path: model mapping to libleptris descriptor
    # plan, native walk, direct hydration. Everything under this
    # namespace is bound to the leptris gem; nothing above it may
    # reference leptris types directly (the moxml adapters and the
    # interpretive path never enter here).
    module Leptris
      # Single capability floor (leptris 1.9.336.0): the child-handles
      # snapshot (1.9.273), exact-URI attribute rows (#1486, 1.9.289),
      # nested-attribute capture (#1563, 1.9.313), wildcard rows
      # (#1552, 1.9.313), child-row ns_uri retention and qualified
      # attribute leniency (#1585/#1586, 1.9.320), the :unqualified ns
      # form (#1560, 1.9.323), and build_result with the address-based
      # text attach (#408, 1.9.334/1.9.336). Bundles resolving an
      # older gem keep the interpretive path — PlanCompiler.compile
      # answers nil — the opt-out protocol.
      MIN_LEPTRIS_VERSION = "1.9.336.0"

      def self.plan_path_compatible?
        return false unless defined?(Gem)

        spec = Gem.loaded_specs["leptris"]
        spec && spec.version >= Gem::Version.new(MIN_LEPTRIS_VERSION)
      end

      autoload :PlanCompiler, "lutaml/xml/leptris/plan_compiler"
      autoload :PlanHydrator, "lutaml/xml/leptris/plan_hydrator"
      autoload :PlanOrder, "lutaml/xml/leptris/plan_order"
      autoload :PlanSerializer, "lutaml/xml/leptris/plan_serializer"
      autoload :PlanWalk, "lutaml/xml/leptris/plan_walk"
    end
  end
end
