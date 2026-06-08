# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Lightweight accumulator used by ElementVisitor when collecting the
        # children of a transient construct (`<group>`, `<choice>`) before
        # promoting them into a Definitions::Sequence or Definitions::Choice on
        # the real Definitions::Model.
        #
        # Mirrors the surface ElementVisitor expects on a model
        # (members, imports, mixed, text_content) but with no XML root,
        # documentation, or namespace — none of which apply to a scratch
        # container.
        class MemberCollector
          attr_reader :members, :imports
          attr_accessor :mixed, :text_content

          def initialize
            @members = []
            @imports = []
            @mixed = false
            @text_content = false
          end
        end
      end
    end
  end
end
