# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # An ordered group of members (Attributes and nested Sequences). At the
        # attribute-declaration level, a Sequence is transparent (members are
        # emitted flat — matching XmlCompiler::Sequence#to_attributes). In the
        # XML mapping block it wraps its members in `sequence do ... end` to
        # preserve the ordering semantic.
        class Sequence
          attr_reader :members

          def initialize
            @members = []
          end

          def add(member)
            @members << member unless member.nil?
          end

          # Flat list of Attribute objects this Sequence (recursively)
          # contributes — used for mapping generation and dep analysis.
          def attributes
            @members.flat_map do |m|
              flatten_attributes(m)
            end
          end

          private

          def flatten_attributes(member)
            case member
            when Sequence then member.attributes
            when Choice   then member.alternatives.flat_map { |alt| flatten_attributes(alt) }
            else [member]
            end
          end
        end
      end
    end
  end
end
