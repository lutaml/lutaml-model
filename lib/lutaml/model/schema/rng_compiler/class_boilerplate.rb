# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Thin RNG-side adapter over the shared
        # Lutaml::Model::Schema::ClassBoilerplate mixin. Kept as its own
        # constant so existing `include ClassBoilerplate` lines in
        # RngCompiler renderers (GeneratedClass, SimpleType, UnionType,
        # Namespace) continue to work unchanged.
        module ClassBoilerplate
          def self.included(base)
            base.include(Lutaml::Model::Schema::ClassBoilerplate)
          end
        end
      end
    end
  end
end
