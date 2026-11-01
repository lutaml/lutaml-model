# frozen_string_literal: true

require "rexml/xmltokens"

module REXML
  module Namespace
    attr_reader :name, :expanded_name
    attr_accessor :prefix

    include XMLTokens

    NAME_WITHOUT_NAMESPACE = /^#{NCNAME_STR}$/
    NAMESPLIT = /^(?:(#{NCNAME_STR}):)?(#{NCNAME_STR})/u

    def name=(name)
      @expanded_name = name
      if name.match?(NAME_WITHOUT_NAMESPACE)
        @prefix = ""
        @namespace = ""
        @name = name
      elsif name =~ NAMESPLIT
        if $1
          @prefix = $1
        else
          @prefix = ""
          @namespace = ""
        end
        @name = $2
      elsif name == ""
        @prefix = nil
        @namespace = nil
        @name = nil
      else
        message = "name must be \#{PREFIX}:\#{LOCAL_NAME} or \#{LOCAL_NAME}: "
        message += "<#{name.inspect}>"
        raise ArgumentError, message
      end
    end

    def has_name?(other, ns = nil)
      if ns
        namespace == ns and name == other
      elsif other.include? ":"
        fully_expanded_name == other
      else
        name == other
      end
    end

    alias :local_name :name

    def fully_expanded_name
      ns = prefix
      return "#{ns}:#@name" if ns.size.positive?

      @name
    end
  end
end
