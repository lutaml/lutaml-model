# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Lightweight accumulator used by ElementVisitor when collecting the
        # children of a transient construct (`<group>`, `<choice>`) before
        # promoting them into a Sequence or Choice on the real GeneratedClass.
        #
        # Exposes the same `add_attribute` / `add_choice` / `add_sequence` /
        # `add_import` surface the visitor relies on, but holds no XML name,
        # documentation, fragment flag, or namespace — none of which apply to
        # a scratch container.
        class MemberCollector
          attr_reader :members

          def initialize
            @members = []
          end

          def add_attribute(spec)
            @members.reject! { |m| m.is_a?(Attribute) && m.name == spec.name }
            @members << spec
          end

          def add_choice(choice)
            @members << choice
          end

          def add_sequence(sequence)
            @members << sequence
          end

          # Imports inside a transient container don't have a place to live;
          # discarded silently because the visitor never produces them in
          # these scopes (refs to fragment defines are emitted on the
          # parent_gen, not on the scratch).
          def add_import(_name); end

          # Mixed/text aren't meaningful on a scratch container, but the
          # visitor checks them — accept the writes silently.
          attr_accessor :mixed, :text_content
        end
      end
    end
  end
end
