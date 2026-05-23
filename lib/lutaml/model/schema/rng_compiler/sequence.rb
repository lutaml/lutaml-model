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
              case m
              when Sequence then m.attributes
              when Choice   then m.alternatives
              else [m]
              end
            end
          end
        end
      end
    end
  end
end
