# frozen_string_literal: true

module Lutaml
  # Layout engine seam shipped with the language core. Engine
  # implementations (GraphViz, ELK) register in the render gem.
  module Layout
    autoload :Engine, "lutaml/lml/layout/engine"
  end
end
