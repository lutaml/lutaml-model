# frozen_string_literal: true

module Lutaml
  module Turtle
    class MissingSubjectError < Lutaml::Rdf::Error; end

    class Transform < Lutaml::Rdf::Transform
      def model_to_data(instance, _format, options = {})
        require "rdf/turtle"
        mapping = extract_turtle_mapping(options)
        return "" unless mapping

        if !mapping.rdf_subject && mapping.rdf_predicates.any? && mapping.rdf_members.empty?
          raise MissingSubjectError,
                "Turtle mapping requires a subject block"
        end

        graph = build_graph(mapping, instance)
        return "" if graph.empty?

        prefixes = build_prefixes(mapping, instance)
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

      private

      def extract_turtle_mapping(options)
        options[:mappings] || mappings_for(:turtle, lutaml_register)
      end

      def build_graph(mapping, instance)
        graph = RDF::Graph.new

        has_predicates_or_type = mapping.rdf_type || mapping.rdf_predicates.any?

        if has_predicates_or_type
          subject_uri = if mapping.rdf_subject
                          RDF::URI(resolve_subject_uri(mapping, instance))
                        else
                          RDF::Node.new
                        end

          if mapping.rdf_type
            type_uri = RDF::URI(resolve_type_uri(mapping))
            graph << RDF::Statement.new(subject_uri, RDF.type, type_uri)
          end

          mapping.rdf_predicates.each do |rule|
            value = instance.public_send(rule.to)
            next if value.nil?

            Array(value).each do |v|
              object = build_rdf_object(v, rule)
              graph << RDF::Statement.new(subject_uri, RDF::URI(rule.uri),
                                          object)
            end
          end
        end

        mapping.rdf_members.each do |member_rule|
          collection = Array(instance.public_send(member_rule.attr_name))
          collection.each do |member|
            member_mapping = member.class.mappings[:turtle]
            next unless member_mapping

            graph << build_graph(member_mapping, member)
          end
        end

        graph
      end

      def build_rdf_object(value, rule)
        if rule.lang_tagged
          lang = extract_language(value)
          RDF::Literal.new(value.to_s, language: lang)
        else
          case value
          when Integer then RDF::Literal.new(value, datatype: RDF::XSD.integer)
          when Float then RDF::Literal.new(value, datatype: RDF::XSD.double)
          when TrueClass, FalseClass then RDF::Literal.new(value, datatype: RDF::XSD.boolean)
          else RDF::Literal.new(value.to_s)
          end
        end
      end

      def build_prefixes(mapping, instance)
        ns_set = mapping.namespace_set

        mapping.rdf_members.each do |member_rule|
          collection = Array(instance.public_send(member_rule.attr_name))
          next if collection.empty?

          member_mapping = collection.first.class.mappings[:turtle]
          next unless member_mapping

          ns_set = ns_set.merge(member_mapping.namespace_set)
        end

        ns_set.each.with_object({}) do |ns, h|
          h[ns.prefix.to_sym] = ns.uri if ns.prefix && ns.uri
        end
      end

      def extract_attributes(graph, mapping)
        attrs = {}
        type_uri = resolve_type_uri(mapping)

        matching_subjects = find_subjects_by_type(graph, type_uri)

        matching_subjects.each do |subject|
          mapping.rdf_predicates.each do |rule|
            stmts = graph.query([subject, RDF::URI(rule.uri), nil])
            next if stmts.empty?

            values = stmts.map { |s| literal_to_ruby(s.object) }
            attrs[rule.to] = values.length == 1 ? values.first : values
          end
        end

        attrs
      end

      def find_subjects_by_type(graph, type_uri)
        graph.query([nil, RDF.type, RDF::URI(type_uri)]).map(&:subject).uniq
      end

      def literal_to_ruby(rdf_object)
        case rdf_object
        when RDF::Literal
          case rdf_object.datatype
          when RDF::XSD.integer then rdf_object.value.to_i
          when RDF::XSD.double, RDF::XSD.decimal, RDF::XSD.float then rdf_object.value.to_f
          when RDF::XSD.boolean then rdf_object.value == "true"
          else rdf_object.value
          end
        else
          rdf_object.to_s
        end
      end
    end
  end
end
