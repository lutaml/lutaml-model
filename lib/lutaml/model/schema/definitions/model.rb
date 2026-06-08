# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # One generated Lutaml::Model::Serializable subclass.
        class Model
          attr_accessor :class_name, :xml_root, :members,
                        :parent_class, :namespace_class_name,
                        :mixed, :text_content, :imports,
                        :documentation, :simple_content, :required_files,
                        :module_wrappable, :lazy_register

          def initialize(class_name:, xml_root:, members: [],
                         parent_class: "Lutaml::Model::Serializable",
                         namespace_class_name: nil,
                         mixed: false, text_content: false,
                         imports: [], documentation: nil,
                         simple_content: nil, required_files: [],
                         module_wrappable: true, lazy_register: false)
            @class_name = class_name
            @xml_root = xml_root
            @members = members
            @parent_class = parent_class
            @namespace_class_name = namespace_class_name
            @mixed = mixed
            @text_content = text_content
            @imports = imports
            @documentation = documentation
            @simple_content = simple_content
            @required_files = required_files
            @module_wrappable = module_wrappable
            @lazy_register = lazy_register
          end
        end
      end
    end
  end
end
