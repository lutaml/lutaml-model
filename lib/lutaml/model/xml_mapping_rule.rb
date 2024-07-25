# lib/lutaml/model/xml_mapping_rule.rb
require_relative "mapping_rule"

module Lutaml
  module Model
    class XmlMappingRule < MappingRule
      attr_reader :namespace, :prefix

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/ParameterLists
      def initialize(
        name,
        to:,
        render_nil: false,
        with: {},
        delegate: nil,
        namespace: nil,
        prefix: nil,
        mixed_content: false
      )
        super(
          name,
          to: to,
          render_nil: render_nil,
          with: with,
          delegate: delegate,
          mixed_content: mixed_content
        )

        @namespace = if namespace.to_s == "inherit"
                       # we are using inherit_namespace in xml builder by
                       # default so no need to do anything here.
                     else
                       namespace
                     end
        @prefix = prefix
      end
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/ParameterLists
    end
  end
end
