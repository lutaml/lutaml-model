# frozen_string_literal: true

module Lutaml
  module Lml
    module Format
      module Adapter
        class Mapping < Lutaml::KeyValue::Mapping
          def initialize
            super(:lml)
          end

          def dup_instance
            self.class.new
          end

          # RS 3001 §String values: a present value — including a
          # zero-length string — is distinct from an absent one, so the
          # lml format emits empty values. Nil stays omitted: absence is
          # the unassigned line, not a rendered null.
          def map(name = nil, to: nil, render_empty: true, **options, &block)
            super(name, to: to, render_empty: render_empty, **options, &block)
          end
          # The parent's `alias map_element map` binds the alias to the
          # parent method at definition time, so it bypasses the map
          # override above; default_mappings goes through map_element.
          alias map_element map
        end
      end
    end
  end
end
