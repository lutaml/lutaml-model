# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Internal value object describing one attribute on a generated class.
        class Attribute
          attr_reader :name, :type, :xml_name, :kind, :collection
          attr_accessor :initialize_empty, :documentation, :default

          def initialize(name:, type:, xml_name:, kind:, collection: nil,
                         initialize_empty: false, documentation: nil,
                         default: nil)
            @name = name
            @type = type
            @xml_name = xml_name
            @kind = kind
            @collection = collection
            @initialize_empty = initialize_empty
            @documentation = documentation
            @default = default
          end

          def attribute_options
            opts = []
            opts << collection_option if @collection
            opts << "default: -> { #{@default.inspect} }" if @default
            opts << "initialize_empty: true" if @initialize_empty
            opts.empty? ? "" : ", #{opts.join(', ')}"
          end

          def type_literal
            case @type
            when Symbol then ":#{@type}"
            else @type.to_s
            end
          end

          private

          def collection_option
            case @collection
            when true then "collection: true"
            when Range
              left = @collection.begin
              right = if @collection.end.respond_to?(:infinite?) && @collection.end.infinite?
                        "Float::INFINITY"
                      else
                        @collection.end
                      end
              "collection: #{left}..#{right}"
            end
          end
        end
      end
    end
  end
end
