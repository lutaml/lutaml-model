require_relative "../mapping/mapping"
require_relative "mapping_rule"

module Lutaml
  module Model
    module Xml
      class Mapping < Mapping
        TYPES = {
          attribute: :map_attribute,
          element: :map_element,
          content: :map_content,
          all_content: :map_all,
        }.freeze

        attr_reader :root_element,
                    :namespace_uri,
                    :namespace_prefix,
                    :mixed_content,
                    :ordered,
                    :element_sequence,
                    :mappings_imported

        def initialize
          super

          @elements = {}
          @attributes = {}
          @element_sequence = []
          @content_mapping = nil
          @raw_mapping = nil
          @mixed_content = false
          @format = :xml
          @mappings_imported = true
          @finalized = false
        end

        def finalize(mapper_class)
          if !root_element && !no_root?
            root(mapper_class.model.to_s)
          end
          @finalized = true
        end

        def finalized?
          @finalized
        end

        alias mixed_content? mixed_content
        alias ordered? ordered

        def root(name, mixed: false, ordered: false)
          @root_element = name
          @mixed_content = mixed
          @ordered = ordered || mixed # mixed contenet will always be ordered
        end

        def root?
          !!root_element
        end

        def no_root
          @no_root = true
        end

        def no_root?
          !!@no_root
        end

        def prefixed_root
          if namespace_uri && namespace_prefix
            "#{namespace_prefix}:#{root_element}"
          else
            root_element
          end
        end

        def namespace(uri, prefix = nil)
          raise Lutaml::Model::NoRootNamespaceError if no_root?

          @namespace_uri = uri
          @namespace_prefix = prefix
        end

        def map_instances(to:, polymorphic: {})
          map_element(to, to: to, polymorphic: polymorphic)
        end

        def map_element(
          name,
          to: nil,
          render_nil: false,
          render_default: false,
          render_empty: false,
          treat_nil: :nil,
          treat_empty: :empty,
          treat_omitted: :nil,
          with: {},
          delegate: nil,
          cdata: false,
          polymorphic: {},
          namespace: (namespace_set = false
                      nil),
          prefix: (prefix_set = false
                   nil),
          transform: {},
          value_map: {}
        )
          validate!(
            name, to, with, render_nil, render_empty, type: TYPES[:element]
          )

          rule = MappingRule.new(
            name,
            to: to,
            render_nil: render_nil,
            render_default: render_default,
            render_empty: render_empty,
            treat_nil: treat_nil,
            treat_empty: treat_empty,
            treat_omitted: treat_omitted,
            with: with,
            delegate: delegate,
            cdata: cdata,
            namespace: namespace,
            default_namespace: namespace_uri,
            prefix: prefix,
            polymorphic: polymorphic,
            namespace_set: namespace_set != false,
            prefix_set: prefix_set != false,
            transform: transform,
            value_map: value_map,
          )
          @elements[rule.namespaced_name] = rule
        end

        def map_attribute(
          name,
          to: nil,
          render_nil: false,
          render_default: false,
          render_empty: false,
          with: {},
          delegate: nil,
          polymorphic_map: {},
          namespace: (namespace_set = false
                      nil),
          prefix: (prefix_set = false
                   nil),
          transform: {},
          value_map: {},
          as_list: nil,
          delimiter: nil
        )
          validate!(
            name, to, with, render_nil, render_empty, type: TYPES[:attribute]
          )

          if name == "schemaLocation"
            Logger.warn_auto_handling(
              name: name,
              caller_file: File.basename(caller_locations(1, 1)[0].path),
              caller_line: caller_locations(1, 1)[0].lineno,
            )
          end

          rule = MappingRule.new(
            name,
            to: to,
            render_nil: render_nil,
            render_default: render_default,
            with: with,
            delegate: delegate,
            namespace: namespace,
            prefix: prefix,
            attribute: true,
            polymorphic_map: polymorphic_map,
            default_namespace: namespace_uri,
            namespace_set: namespace_set != false,
            prefix_set: prefix_set != false,
            transform: transform,
            value_map: value_map,
            as_list: as_list,
            delimiter: delimiter,
          )
          @attributes[rule.namespaced_name] = rule
        end

        def map_content(
          to: nil,
          render_nil: false,
          render_default: false,
          render_empty: false,
          with: {},
          delegate: nil,
          mixed: false,
          cdata: false,
          transform: {},
          value_map: {}
        )
          validate!(
            "content", to, with, render_nil, render_empty, type: TYPES[:content]
          )

          @content_mapping = MappingRule.new(
            nil,
            to: to,
            render_nil: render_nil,
            render_default: render_default,
            render_empty: render_empty,
            with: with,
            delegate: delegate,
            mixed_content: mixed,
            cdata: cdata,
            transform: transform,
            value_map: value_map,
          )
        end

        def map_all(
          to:,
          render_nil: false,
          render_default: false,
          delegate: nil,
          with: {},
          namespace: (namespace_set = false
                      nil),
          prefix: (prefix_set = false
                   nil),
          render_empty: false
        )
          validate!(
            Constants::RAW_MAPPING_KEY,
            to,
            with,
            render_nil,
            render_empty,
            type: TYPES[:all_content],
          )

          rule = MappingRule.new(
            Constants::RAW_MAPPING_KEY,
            to: to,
            render_nil: render_nil,
            render_default: render_default,
            with: with,
            delegate: delegate,
            namespace: namespace,
            prefix: prefix,
            default_namespace: namespace_uri,
            namespace_set: namespace_set != false,
            prefix_set: prefix_set != false,
          )

          @raw_mapping = rule
        end

        alias map_all_content map_all

        def sequence(&block)
          @element_sequence << Sequence.new(self).tap { |s| s.instance_eval(&block) }
        end

        def import_model_mappings(model)
          return import_mappings_later(model) if model_importable?(model)
          raise Lutaml::Model::ImportModelWithRootError.new(model) if model.root?

          mappings = model.mappings_for(:xml)
          @elements.merge!(mappings.instance_variable_get(:@elements))
          @attributes.merge!(mappings.instance_variable_get(:@attributes))
          (@element_sequence << mappings.element_sequence).flatten!
        end

        def set_mappings_imported(value)
          @mappings_imported = value
        end

        def validate!(key, to, with, render_nil, render_empty, type: nil)
          validate_raw_mappings!(type)
          validate_to_and_with_arguments!(key, to, with)

          if render_nil == :as_empty || render_empty == :as_empty
            raise IncorrectMappingArgumentsError.new(
              ":as_empty is not supported for XML mappings",
            )
          end
        end

        def validate_to_and_with_arguments!(key, to, with)
          if to.nil? && with.empty?
            raise IncorrectMappingArgumentsError.new(
              ":to or :with argument is required for mapping '#{key}'",
            )
          end

          validate_with_options!(key, to, with)
        end

        def validate_with_options!(key, to, with)
          return true if to

          if !with.empty? && (with[:from].nil? || with[:to].nil?)
            raise IncorrectMappingArgumentsError.new(
              ":with argument for mapping '#{key}' requires :to and :from keys",
            )
          end
        end

        def validate_raw_mappings!(type)
          if !@raw_mapping.nil? && type != TYPES[:attribute]
            raise StandardError, "#{type} is not allowed, only #{TYPES[:attribute]} " \
                                 "is allowed with #{TYPES[:all_content]}"
          end

          if !(elements.empty? && content_mapping.nil?) && type == TYPES[:all_content]
            raise StandardError, "#{TYPES[:all_content]} is not allowed with other mappings"
          end
        end

        def elements
          @elements.values
        end

        def attributes
          @attributes.values
        end

        def content_mapping
          @content_mapping
        end

        def raw_mapping
          @raw_mapping
        end

        def mappings(register_id = nil)
          ensure_mappings_imported!(register_id) if finalized?
          elements + attributes + [content_mapping, raw_mapping].compact
        end

        def ensure_mappings_imported!(register_id = nil)
          return if @mappings_imported

          importable_mappings.each do |model|
            import_model_mappings(
              register(register_id).get_class_without_register(model),
            )
          end

          sequence_importable_mappings.each do |sequence, models|
            models.each do |model|
              sequence.import_model_mappings(
                register(register_id).get_class_without_register(model),
              )
            end
          end

          @mappings_imported = true
        end

        def importable_mappings
          @importable_mappings ||= []
        end

        def sequence_importable_mappings
          @sequence_importable_mappings ||= ::Hash.new { |h, k| h[k] = [] }
        end

        def element(name)
          elements.detect { |rule| name == rule.to }
        end

        def attribute(name)
          attributes.detect { |rule| name == rule.to }
        end

        def find_by_name(name, type: "Text")
          return content_mapping if text_content_name?(name, type)

          mappings.detect { |rule| name_matches_rule?(name, rule) }
        end

        def find_by_to(to)
          mappings.detect { |rule| rule.to.to_s == to.to_s }
        end

        def find_by_to!(to)
          mapping = find_by_to(to)

          return mapping if !!mapping

          raise raise Lutaml::Model::NoMappingFoundError.new(to.to_s)
        end

        def mapping_attributes_hash
          @attributes
        end

        def mapping_elements_hash
          @elements
        end

        def merge_mapping_attributes(mapping)
          mapping_attributes_hash.merge!(mapping.mapping_attributes_hash)
        end

        def merge_mapping_elements(mapping)
          mapping_elements_hash.merge!(mapping.mapping_elements_hash)
        end

        def merge_elements_sequence(mapping)
          mapping.element_sequence.each do |sequence|
            element_sequence << Lutaml::Model::Sequence.new(self).tap do |instance|
              sequence.attributes.each do |attr|
                instance.attributes << attr.deep_dup
              end
            end
          end
        end

        def deep_dup
          self.class.new.tap do |xml_mapping|
            xml_mapping.root(@root_element.dup, mixed: @mixed_content,
                                                ordered: @ordered)
            xml_mapping.namespace(@namespace_uri.dup, @namespace_prefix.dup) if @namespace_uri

            attributes_to_dup.each do |var_name|
              value = instance_variable_get(var_name)
              xml_mapping.instance_variable_set(var_name, Utils.deep_dup(value))
            end
            xml_mapping.instance_variable_set(:@finalized, true)
          end
        end

        def polymorphic_mapping
          mappings.find(&:polymorphic_mapping?)
        end

        def attributes_to_dup
          @attributes_to_dup ||= %i[
            @content_mapping
            @raw_mapping
            @element_sequence
            @attributes
            @elements
          ]
        end

        def dup_mappings(mappings)
          new_mappings = {}

          mappings.each do |key, mapping_rule|
            new_mappings[key] = mapping_rule.deep_dup
          end

          new_mappings
        end

        private

        def text_content_name?(name, type)
          ["text", "#cdata-section"].include?(name.to_s) && type == "Text"
        end

        def name_matches_rule?(name, rule)
          rule.name == name.to_s ||
            rule.name == name.to_sym ||
            (rule.respond_to?(:prefixed_name) && rule.prefixed_name == name.to_s)
        end

        def register(register_id = nil)
          register_id ||= Lutaml::Model::Config.default_register
          Lutaml::Model::GlobalRegister.lookup(register_id)
        end

        def model_importable?(model)
          model.is_a?(Symbol) || model.is_a?(String)
        end

        def import_mappings_later(model)
          importable_mappings << model.to_sym
          @mappings_imported = false
        end
      end
    end
  end
end
