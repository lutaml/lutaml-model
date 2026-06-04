# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      # Stateless helpers for emitting `module Foo ... end` wrappers around
      # generated code, given an Array of module-name segments.
      #
      # Both helpers return a single newline-terminated block (no trailing
      # newline) so ERB templates should use `<%= ... -%>` to avoid
      # doubling the line break.
      module ModuleNesting
        module_function

        def opening(modules)
          return "" if modules.empty?

          modules.map.with_index { |m, i| "#{'  ' * i}module #{m}\n" }.join
        end

        def closing(modules)
          return "" if modules.empty?

          modules.reverse.map.with_index do |_m, i|
            "#{'  ' * (modules.size - i - 1)}end\n"
          end.join
        end
      end
    end
  end
end
