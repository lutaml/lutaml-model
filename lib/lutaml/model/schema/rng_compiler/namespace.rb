# frozen_string_literal: true

require "erb"
require "uri"

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Generates a Lutaml::Xml::W3c::XmlNamespace subclass from the RNG
        # grammar's `ns` attribute. Mirrors XmlCompiler::XmlNamespaceClass.
        class Namespace
          include ClassBoilerplate

          attr_reader :fragment
          attr_accessor :uri, :prefix_default, :class_name

          TEMPLATE = ERB.new(<<~TMPL, trim_mode: "-")
            # frozen_string_literal: true

            require "lutaml/model"

            <%= module_opening -%>
            # Namespace: <%= uri %>
            class <%= class_name %> < Lutaml::Xml::W3c::XmlNamespace
              uri <%= uri.inspect %>
              prefix_default <%= prefix_default.inspect %>
            end
            <%= module_closing -%>
          TMPL

          def type_symbol
            Utils.snake_case(class_name).to_sym
          end

          def initialize(uri:, prefix: nil, class_name: nil)
            @uri = uri
            @prefix_default = prefix || derive_prefix(uri)
            @class_name = class_name || derive_class_name(uri)
            @module_namespace = nil
            @fragment = true
          end

          def render(indent: 2, module_namespace: nil, register_id: :default)
            _ = indent
            _ = register_id
            @module_namespace = module_namespace
            @modules = Array(module_namespace&.split("::"))
            TEMPLATE.result(binding)
          end

          private

          def derive_prefix(uri)
            case uri
            when %r{/math$}      then "m"
            when %r{XMLSchema}   then "xs"
            when %r{/(\w+)\z}    then ::Regexp.last_match(1)[0..2]
            else "ns"
            end
          end

          def derive_class_name(uri)
            parsed = URI.parse(uri)
            host_parts = (parsed.host&.split(".") || []).reject(&:empty?)
            path_parts = (parsed.path&.split("/") || []).reject(&:empty?)

            name_parts = host_parts.reverse.take(2) + path_parts.last(2)
            name_parts = name_parts.map do |p|
              Utils.camel_case(p.gsub(/\d+/, "").gsub(/[^a-zA-Z]/, ""))
            end.reject(&:empty?)

            return "DefaultNamespace" if name_parts.empty?

            "#{name_parts.join}Namespace"
          rescue StandardError
            "DefaultNamespace"
          end
        end
      end
    end
  end
end
