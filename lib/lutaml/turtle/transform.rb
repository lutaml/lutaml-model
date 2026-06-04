# frozen_string_literal: true

module Lutaml
  module Turtle
    class MissingSubjectError < Lutaml::Rdf::Error; end

    class Transform < Lutaml::Rdf::Transform
      def model_to_data(instance, _format, options = {})
        require "rdf/turtle"
        mapping = extract_turtle_mapping(options)
        return "" unless mapping

        if !mapping.rdf_subject && mapping.has_types_or_predicates? && mapping.rdf_members.empty?
          raise MissingSubjectError,
                "Turtle mapping requires a subject block"
        end

        graph = build_graph(mapping, instance)
        return "" if graph.empty?

        prefixes = collect_all_prefixes(mapping, instance)
        RDF::Turtle::Writer.buffer(prefixes: prefixes) do |writer|
          graph.each_statement { |stmt| writer << stmt }
        end.strip
      end

      def data_to_model(data, _format, options = {})
        require "rdf/turtle"
        mapping = extract_turtle_mapping(options)
        unless mapping&.rdf_subject
          raise MissingSubjectError,
                "Turtle mapping requires a subject block"
        end

        graph = data.is_a?(RDF::Graph) ? data : Lutaml::Turtle::Adapter.parse(data)
        attrs = extract_attributes(graph, mapping)
        build_instance(attrs, options)
      end

      protected

      def additional_resource_triples(_instance, _subject_uri, _mapping)
        []
      end

      private

      def extract_turtle_mapping(options)
        options[:mappings] || mappings_for(:turtle, lutaml_register)
      end

      def build_graph(mapping, instance)
        graph = RDF::Graph.new

        has_resource_data =
          mapping.has_types_or_predicates? ||
          mapping.rdf_members.any?(&:linked?)

        if has_resource_data
          subject_uri = if mapping.rdf_subject
                          RDF::URI(resolve_subject_uri(mapping, instance))
                        else
                          RDF::Node.new
                        end

          emit_type_statements(graph, subject_uri, mapping)
          emit_predicate_statements(graph, subject_uri, instance, mapping)
          emit_member_link_statements(graph, subject_uri, instance, mapping)
          additional_resource_triples(instance, subject_uri,
                                      mapping).each do |stmt|
            graph << stmt
          end
        end

        emit_child_resources(graph, instance, mapping)

        graph
      end

      def emit_type_statements(graph, subject_uri, mapping)
        mapping.rdf_type.each do |type_value|
          type_uri = RDF::URI(resolve_single_type_uri(mapping, type_value))
          graph << RDF::Statement.new(subject_uri, RDF.type, type_uri)
        end
      end

      def emit_predicate_statements(graph, subject_uri, instance, mapping)
        mapping.rdf_predicates.each do |rule|
          value = instance.public_send(rule.to)
          next if value.nil?

          Array(value).each do |v|
            next if v.is_a?(String) && v.empty?

            object = build_rdf_object(v, rule, mapping.namespace_set)
            graph << RDF::Statement.new(subject_uri, RDF::URI(rule.uri), object)
          end
        end
      end

      def emit_member_link_statements(graph, subject_uri, instance, mapping)
        mapping.rdf_members.each do |member_rule|
          next unless member_rule.linked?

          each_member(instance, member_rule) do |member|
            member_mapping = member_mapping_for(member, :turtle)
            next unless member_mapping&.rdf_subject

            child_uri = RDF::URI(resolve_subject_uri(member_mapping, member))
            resolver = mapping.namespace_set.method(:resolve_compact_iri)
            link_uri = RDF::URI(member_rule.resolve_link_uri(member, resolver))
            next unless link_uri

            graph << RDF::Statement.new(subject_uri, link_uri, child_uri)
          end
        end
      end

      def emit_child_resources(graph, instance, mapping)
        mapping.rdf_members.each do |member_rule|
          each_member(instance, member_rule) do |member|
            member_mapping = member_mapping_for(member, :turtle)
            next unless member_mapping

            graph << build_graph(member_mapping, member)
          end
        end
      end

      def build_rdf_object(value, rule, namespace_set)
        case rule.kind
        when :uri_reference
          build_uri_reference_object(value, namespace_set)
        when :lang_tagged
          lang = extract_language(value)
          RDF::Literal.new(value.to_s, language: lang)
        else
          build_plain_literal(value)
        end
      end

      def build_uri_reference_object(value, namespace_set)
        resolved = if value.to_s.include?(":")
                     namespace_set.resolve_compact_iri(value.to_s)
                   else
                     value.to_s
                   end
        RDF::URI.new(resolved)
      end

      def build_plain_literal(value)
        case value
        when Integer then RDF::Literal.new(value, datatype: RDF::XSD.integer)
        when Float then RDF::Literal.new(value, datatype: RDF::XSD.double)
        when TrueClass, FalseClass then RDF::Literal.new(value, datatype: RDF::XSD.boolean)
        else RDF::Literal.new(value.to_s)
        end
      end

      def collect_all_prefixes(mapping, instance)
        ns_set = collect_namespaces_recursive(mapping, instance)
        ns_set.each.with_object({}) do |ns, h|
          h[ns.prefix.to_sym] = ns.uri if ns.prefix && ns.uri
        end
      end

      def collect_namespaces_recursive(mapping, instance)
        ns_set = mapping.namespace_set

        mapping.rdf_members.each do |member_rule|
          each_member(instance, member_rule) do |member|
            member_mapping = member_mapping_for(member, :turtle)
            next unless member_mapping

            ns_set = ns_set.merge(member_mapping.namespace_set)
            child_ns = collect_namespaces_recursive(member_mapping, member)
            ns_set = ns_set.merge(child_ns)
          end
        end

        ns_set
      end

      def extract_attributes(graph, mapping)
        attrs = {}
        type_uris = resolve_type_uris(mapping)

        matching_subjects = find_subjects_by_types(graph, type_uris)

        matching_subjects.each do |subject|
          attrs["id"] = subject.to_s unless subject.node?
          extract_predicate_attributes(graph, subject, mapping, attrs)
        end

        attrs
      end

      def find_subjects_by_types(graph, type_uris)
        type_uris.flat_map do |type_uri|
          graph.query([nil, RDF.type, RDF::URI(type_uri)]).map(&:subject).uniq
        end.uniq
      end

      def extract_predicate_attributes(graph, subject, mapping, attrs)
        mapping.rdf_predicates.each do |rule|
          stmts = graph.query([subject, RDF::URI(rule.uri), nil])
          next if stmts.empty?

          values = stmts.map do |s|
            literal_to_ruby(s.object, rule, mapping.namespace_set)
          end
          attrs[rule.to] = values.length == 1 ? values.first : values
        end
      end

      def literal_to_ruby(rdf_object, rule, namespace_set)
        case rdf_object
        when RDF::URI
          uri_to_ruby(rdf_object, rule, namespace_set)
        when RDF::Literal
          literal_value_to_ruby(rdf_object, rule)
        else
          rdf_object.to_s
        end
      end

      def uri_to_ruby(rdf_object, rule, namespace_set)
        uri_str = rdf_object.to_s
        if rule.kind == :uri_reference
          namespace_set.compact(uri_str) || uri_str
        else
          uri_str
        end
      end

      def literal_value_to_ruby(rdf_object, rule)
        if rule.kind == :lang_tagged && rdf_object.language
          rdf_object.value
        else
          case rdf_object.datatype
          when RDF::XSD.integer then rdf_object.value.to_i
          when RDF::XSD.double, RDF::XSD.decimal, RDF::XSD.float then rdf_object.value.to_f
          when RDF::XSD.boolean then rdf_object.value == "true"
          else rdf_object.value
          end
        end
      end
    end
  end
end
