# frozen_string_literal: true

require "json"

module Lutaml
  module Lml
    module Lsp
      # The completion keyword list, read from the compiled grammar
      # artifact so it cannot drift from the language.
      module Keywords
        ARTIFACT = File.expand_path("../grammar/lml.artifact.json", __dir__)

        module_function

        def all
          @all ||= begin
            artifact = JSON.parse(File.read(ARTIFACT))
            literals = []
            collect(artifact["entries"], literals)
            literals.grep(/\A[a-z][a-z0-9_]*\z/)
                    .uniq
                    .sort
          end
        end

        def collect(node, literals)
          case node
          when Hash
            node.each do |key, value|
              if key.to_s == "Str" && value.is_a?(Hash)
                literals << value["pattern"].to_s
              else
                collect(value, literals)
              end
            end
          when Array
            node.each { |item| collect(item, literals) }
          end
        end
      end
    end
  end
end
