# frozen_string_literal: true

module Lutaml
  module Formatter
    class << self
      def all
        @all ||= []
      end

      def find_by_name(name)
        name = name.to_sym
        all.detect { |formatter_class| formatter_class.formatter_name == name }
      end
    end

    class Base
      FORMAT_HANDLERS = {
        Lml::TopElementAttribute => :format_attribute,
        Lml::Operation => :format_operation,
        Lml::Association => :format_relationship,
        Lml::Document => :format_document,
        Lml::DataType => :format_class,
        Lml::UmlClass => :format_class,
        Lml::Enum => :format_class
      }.freeze

      class << self
        def inherited(subclass)
          super
          Formatter.all << subclass
        end

        def format(node, attributes = {})
          new(attributes).format(node)
        end

        # Registry key for Formatter.find_by_name. Deliberately not
        # `name` — shadowing Class#name breaks Ruby internals and any
        # library that legitimately calls .name on these classes.
        def formatter_name
          to_s.split('::').last.downcase.to_sym
        end
      end

      include Lml::HasAttributes

      def initialize(attributes = {})
        update_attributes(attributes)
      end

      def name
        self.class.formatter_name
      end

      attr_reader :type

      def type=(value)
        @type = value.to_s.strip.downcase.to_sym
      end

      def format(node)
        dispatch_format(node)
      end

      def dispatch_format(node)
        handler = FORMAT_HANDLERS.find { |type, _| node.is_a?(type) }&.last
        raise Lml::Error, "no format handler for #{node.class}" unless handler

        public_send(handler, node)
      end

      def format_attribute(_node) = raise(NotImplementedError)
      def format_operation(_node) = raise(NotImplementedError)
      def format_relationship(_node) = raise(NotImplementedError)
      def format_class(_node) = raise(NotImplementedError)
      def format_document(_node) = raise(NotImplementedError)
    end
  end
end
