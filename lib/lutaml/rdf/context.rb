# frozen_string_literal: true

module Lutaml
  module Rdf
    class Context
      attr_reader :prefixes, :terms

      def initialize
        @prefixes = {}
        @terms = {}
        @vocab = nil
        @language = nil
        @base = nil
      end

      def prefix(namespace_class)
        @prefixes[namespace_class.prefix] = namespace_class.uri
      end

      def vocab(uri = nil)
        @vocab = uri if uri
        @vocab
      end

      def language(lang = nil)
        @language = lang if lang
        @language
      end

      def base(uri = nil)
        @base = uri if uri
        @base
      end

      def term(name, id: nil, type: nil, container: nil, language: nil,
reverse: false)
        @terms[name] = TermDefinition.new(
          name: name,
          id: id,
          type: type,
          container: container,
          language: language,
          reverse: reverse,
        )
      end

      def to_hash
        ctx = {}
        ctx["@vocab"] = @vocab if @vocab
        ctx["@language"] = @language if @language
        ctx["@base"] = @base if @base
        @prefixes.each { |pfx, uri| ctx[pfx] = uri }
        @terms.each_value { |td| ctx.merge!(td.to_context_hash) }
        ctx
      end

      def resolve(term_name)
        if term_name.include?(":")
          pfx, local = term_name.split(":", 2)
          "#{@prefixes[pfx]}#{local}" if @prefixes.key?(pfx)
        elsif @terms.key?(term_name)
          @terms[term_name].id
        elsif @vocab
          "#{@vocab}#{term_name}"
        end
      end
    end
  end
end
