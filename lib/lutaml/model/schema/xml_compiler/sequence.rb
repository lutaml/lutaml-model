# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Sequence
          attr_accessor :sequences, :elements, :choice, :groups

          INDENT = "  "

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>sequence do
            <%= sequences.map { |object| object.to_class(indent + INDENT) }.join -%>
            <%= choice.map { |object| object.to_class(indent + INDENT) }.join -%>
            <%= elements.map { |object| object.to_class(indent + INDENT) }.join -%>
            <%= indent %>end
          TEMPLATE

          def initialize
            @sequences = []
            @elements = []
            @choice = []
            @groups = []
          end

          def to_class(indent = INDENT)
            TEMPLATE.result(binding)
          end
        end
      end
    end
  end
end
