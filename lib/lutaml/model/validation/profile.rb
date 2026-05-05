# frozen_string_literal: true

require "yaml"

module Lutaml
  module Model
    module Validation
      # Composable validation profile loaded from YAML. Selects which rules
      # run during validation. Profiles can import other profiles for
      # rule reuse across validation levels (e.g., basic → strict).
      class Profile
        attr_reader :name, :description, :rule_names, :imports

        def initialize(name:, description: nil, rule_names: [], imports: [])
          @name = name
          @description = description
          @rule_names = rule_names
          @imports = imports
        end

        def self.load(path)
          data = YAML.safe_load_file(path, symbolize_names: false)
          new(
            name: data["name"],
            description: data["description"],
            rule_names: data["rules"] || [],
            imports: data["import"] || [],
          )
        end

        def resolve(registry, profiles_by_name = {})
          resolved = resolve_imports(registry, profiles_by_name)
          resolved | resolve_names(registry)
        end

        private

        def resolve_names(registry)
          rule_names.filter_map do |name|
            registry.all.find { |r| r.class.name == name }
          end
        end

        def resolve_imports(registry, profiles_by_name)
          imports.flat_map do |import_name|
            imported = profiles_by_name[import_name]
            next [] unless imported

            imported.resolve(registry, profiles_by_name)
          end
        end
      end
    end
  end
end
