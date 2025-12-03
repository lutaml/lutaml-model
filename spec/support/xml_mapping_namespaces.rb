# Namespace class definitions for xml_mapping_spec.rb
# Modernized from string-based to class-based XmlNamespace syntax

class XmiNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.omg.org/spec/XMI/20131001"
  prefix_default "xmi"
end

class XmiNewNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.omg.org/spec/XMI/20161001"
  prefix_default "new"
end

class MathMlNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.w3.org/1998/Math/MathML"
end

class CheckNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.check.com"
  prefix_default "ns1"
end

class ExampleNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.example.com"
  prefix_default "ex1"
end

class GmlNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.sparxsystems.com/profiles/GML/1.0"
  prefix_default "GML"
end

class CityGmlNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.sparxsystems.com/profiles/CityGML/1.0"
  prefix_default "CityGML"
end

class TestingDuplicateNamespace < Lutaml::Model::XmlNamespace
  uri "https://testing-duplicate"
  prefix_default "td"
end

class TestElementNamespace < Lutaml::Model::XmlNamespace
  uri "https://test-element"
  prefix_default "te"
end

class ParentNamespace < Lutaml::Model::XmlNamespace
  uri "http://parent-namespace"
  prefix_default "pn"
end

class ChildNamespace < Lutaml::Model::XmlNamespace
  uri "http://child-namespace"
  prefix_default "cn"
end

class XsdNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.w3.org/2001/XMLSchema"
  prefix_default "xsd"
end

# Namespace for default_namespace_spec.rb
class ExampleNamespaceDefault < Lutaml::Model::XmlNamespace
  uri "http://example.com/ns"
end

# Namespace for mixed_content_spec.rb
class ExampleSchemaNamespace < Lutaml::Model::XmlNamespace
  uri "http://example.com/schema"
  prefix_default "xsd"
end

# Namespaces for xml_adapter/xml_namespace_spec.rb
class TestNamespace < Lutaml::Model::XmlNamespace
  uri "http://example.com/test"
  prefix_default "test"
end

class FooNamespace < Lutaml::Model::XmlNamespace
  uri "http://example.com/foo"
  prefix_default "foo"
end

class XmlLangNamespace < Lutaml::Model::XmlNamespace
  uri "http://example.com/xml"
  prefix_default "xml"
end

class BarNamespace < Lutaml::Model::XmlNamespace
  uri "http://example.com/bar"
  prefix_default "bar"
end

class BazNamespace < Lutaml::Model::XmlNamespace
  uri "http://example.com/baz"
  prefix_default "baz"
end

class TestSchemasNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.test.com/schemas/test/1.0/"
  prefix_default "test"
end

class UnitsNamespace < Lutaml::Model::XmlNamespace
  uri "https://schema.example.org/units/1.0"
end

# Namespace for namespace_spec.rb
class AbcNamespace < Lutaml::Model::XmlNamespace
  uri "https://abc.com"
end

# Namespace for xml/namespace/nested_with_explicit_namespace_spec.rb
class TestBaseNamespace < Lutaml::Model::XmlNamespace
  uri "https://test-namespace"
  prefix_default "test"
end
