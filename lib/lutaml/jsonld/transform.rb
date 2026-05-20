# frozen_string_literal: true

require "json"

module Lutaml
  module JsonLd
    class Transform < Lutaml::Rdf::Transform
      def model_to_data(instance, _format, options = {})
        mapping = extract_mapping(options)
        return {} unless mapping

        if mapping.rdf_members.any?
          build_graph_document(mapping, instance)
        else
          build_resource_object(mapping, instance)
        end
      end

      def data_to_model(data, _format, options = {})
        mapping = extract_mapping(options)
        return model_class.new unless mapping

        hash = data.is_a?(String) ? JSON.parse(data) : data

        if hash.key?("@graph") && hash["@graph"].is_a?(Array) && !hash["@graph"].empty?
          graph_data = hash["@graph"]
          first = graph_data.first
          hash = first.is_a?(Hash) ? first : {}
        end

        hash = strip_jsonld_keywords(hash)

        attrs = {}
        mapping.rdf_predicates.each do |rule|
          value = hash[rule.predicate_name]
          next if value.nil?

          attrs[rule.to] = if rule.kind == :lang_tagged && value.is_a?(Hash)
                             flatten_language_map(value)
                           else
                             value
                           end
        end

        build_instance(attrs, options)
      end

      private

      def extract_mapping(options)
        options[:mappings] || mappings_for(:jsonld, lutaml_register)
      end

      def build_graph_document(mapping, instance)
        context = build_merged_context(mapping, instance)
        graph = []

        if mapping.rdf_subject
          resource = build_resource_data(mapping, instance)
          graph << resource unless resource.empty?
        end

        mapping.rdf_members.each do |member_rule|
          each_member(instance, member_rule) do |member|
            member_mapping = member_mapping_for(member, :jsonld)
            next unless member_mapping

            resource = build_resource_data(member_mapping, member)
            graph << resource unless resource.empty?
          end
        end

        { "@context" => context, "@graph" => graph }
      end

      def build_merged_context(mapping, instance)
        context_hash = build_context_from_mapping(mapping).to_hash

        mapping.rdf_members.each do |member_rule|
          each_member(instance, member_rule) do |member|
            member_mapping = member_mapping_for(member, :jsonld)
            next unless member_mapping

            context_hash.merge!(build_context_from_mapping(member_mapping).to_hash)
          end
        end

        context_hash
      end

      def build_context_from_mapping(mapping)
        context = Context.new
        mapping.namespace_set.each { |ns| context.prefix(ns) }
        mapping.rdf_predicates.each do |pred|
          options = { id: pred.uri }
          term_options = context_term_options(pred)
          context.term(pred.predicate_name, **options, **term_options)
        end

        mapping.rdf_members.each do |member_rule|
          next unless member_rule.linked?

          context.term(member_rule.predicate_name.to_s,
                       id: member_rule.linked_predicate_uri,
                       type: "@id")
        end

        context
      end

      def context_term_options(rule)
        case rule.kind
        when :uri_reference then { type: "@id" }
        when :lang_tagged then { container: :language }
        else {}
        end
      end

      def build_resource_object(mapping, instance)
        context = build_context_from_mapping(mapping).to_hash
        data = build_resource_data(mapping, instance)
        { "@context" => context }.merge(data)
      end

      def build_resource_data(mapping, instance)
        result = {}

        if mapping.rdf_type.any?
          result["@type"] = if mapping.rdf_type.length == 1
                              mapping.rdf_type.first
                            else
                              mapping.rdf_type
                            end
        end

        if mapping.rdf_subject
          result["@id"] = resolve_subject_uri(mapping, instance)
        end

        mapping.rdf_predicates.each do |rule|
          value = instance.public_send(rule.to)
          next if value.nil?
          next if value.is_a?(String) && value.empty?

          result[rule.predicate_name] = serialize_value(value, rule)
        end

        mapping.rdf_members.each do |member_rule|
          next unless member_rule.linked?

          member_refs = collect_member_references(instance, member_rule)
          next if member_refs.empty?

          result[member_rule.predicate_name.to_s] = member_refs
        end

        result
      end

      def collect_member_references(instance, member_rule)
        refs = []
        each_member(instance, member_rule) do |member|
          member_mapping = member_mapping_for(member, :jsonld)
          next unless member_mapping

          refs << { "@id" => resolve_subject_uri(member_mapping, member) }
        end
        refs
      end

      def serialize_value(value, rule)
        case rule.kind
        when :uri_reference then serialize_uri_reference(value)
        when :lang_tagged then build_language_map(value)
        else serialize_rdf_value(value)
        end
      end

      def serialize_uri_reference(value)
        case value
        when Array then value.map { |v| { "@id" => v.to_s } }
        else { "@id" => value.to_s }
        end
      end

      def build_language_map(values)
        case values
        when Array
          map = {}
          values.each do |v|
            lang = extract_language(v)
            map[lang] = v.to_s if lang
          end
          map.empty? ? nil : map
        else
          lang = extract_language(values)
          lang ? { lang => values.to_s } : values.to_s
        end
      end

      def flatten_language_map(lang_map)
        lang_map.values
      end

      def serialize_rdf_value(value)
        case value
        when Array then value.map { |v| serialize_rdf_value(v) }
        when Integer, Float, TrueClass, FalseClass then value
        else value.to_s
        end
      end

      def strip_jsonld_keywords(data)
        return data unless data.is_a?(Hash)

        data.reject { |key, _| key.start_with?("@") }
      end
    end
  end
end
