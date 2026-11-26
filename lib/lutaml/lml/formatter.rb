# frozen_string_literal: true

module Lutaml
  # Output formatters shipped with the language core. Diagram-rendering
  # backends (Graphviz, ELK, SVG/PDF) register in the render gem and
  # autoload against the same seam.
  module Formatter
    autoload :Base, "lutaml/lml/formatter/base"
    autoload :Canonical, "lutaml/lml/formatter/canonical"
  end
end
