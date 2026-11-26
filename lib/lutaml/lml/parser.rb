# frozen_string_literal: true

module Lutaml
  module Lml
    # The LML parser: raw LML text → parse tree. The grammar lives in
    # grammar/lml.parg (PARG); this class is the Ruby-facing front door.
    # Pipeline-level entry points live on the Lutaml::Lml module
    # (parse / parse_document).
    class Parser
      def self.parse(input, **options)
        new.parse(input, **options)
      end

      def parse(input, **_options)
        Grammar.artifact.parse(Grammar::ENTRY, input.to_s)
      end
    end
  end
end
