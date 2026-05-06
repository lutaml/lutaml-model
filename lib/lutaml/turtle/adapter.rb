# frozen_string_literal: true

module Lutaml
  module Turtle
    class Adapter
      attr_reader :data, :register

      def initialize(data, register: nil)
        @data = data
        @register = register || Lutaml::Model::Config.default_register
      end

      def self.parse(turtle_string, _options = {})
        require "rdf/turtle"
        graph = RDF::Graph.new
        RDF::Turtle::Reader.new(turtle_string).each_statement do |stmt|
          graph << stmt
        end
        graph
      end

      def to_turtle(_options = {})
        require "rdf/turtle"
        case data
        when String
          data
        when RDF::Enumerable
          RDF::Turtle::Writer.buffer { |w| data.each_statement { |s| w << s } }
        else
          data.to_s
        end
      end
    end
  end
end
