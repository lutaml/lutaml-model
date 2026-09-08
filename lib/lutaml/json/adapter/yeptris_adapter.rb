# frozen_string_literal: true

require "yeptris"
require_relative "standard_adapter"

module Lutaml
  module Json
    module Adapter
      # JSON parsing over the yeptris engine: Yeptris::JSON.load targets
      # exact JSON.parse semantics (spec-pinned upstream), with a fused
      # native materializer when the loaded libyeptris build carries it.
      # Generation stays on the json gem (the yeptris JSON surface is
      # load-only), so everything else inherits from the standard adapter.
      class YeptrisAdapter < StandardAdapter
        def self.parse(json, _options = {})
          ::Yeptris::JSON.load(json)
        end
      end
    end
  end
end
