# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # Restricted simple type — `class X < Lutaml::Model::Type::Y`
        # with a cast body that applies facets and delegates to super.
        class RestrictedType
          attr_accessor :class_name, :parent_class, :base_class, :facets,
                        :transform_facet, :required_files,
                        :keep_register_when_namespaced, :namespace_class_name

          def initialize(class_name:, facets:, parent_class: nil,
                         base_class: nil, transform_facet: nil,
                         required_files: [],
                         keep_register_when_namespaced: false,
                         namespace_class_name: nil)
            @class_name = class_name
            @parent_class = parent_class
            @base_class = base_class
            @facets = facets
            @transform_facet = transform_facet
            @required_files = required_files
            @keep_register_when_namespaced = keep_register_when_namespaced
            @namespace_class_name = namespace_class_name
          end
        end
      end
    end
  end
end
