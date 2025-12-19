# Namespace class definitions for xml_mapping_spec.rb
# Modernized from string-based to class-based XmlNamespace syntax

class XmiNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.omg.org/spec/XMI/20131001"
  prefix_default "xmi"
  element_form_default :qualified
end

class XmiNewNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.omg.org/spec/XMI/20161001"
  prefix_default "new"
  element_form_default :qualified
end

class MathMlNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.w3.org/1998/Math/MathML"
  element_form_default :qualified
end

class CheckNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.check.com"
  prefix_default "ns1"
  element_form_default :qualified
end

class ExampleNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.example.com"
  prefix_default "ex1"
  element_form_default :qualified
end

class GmlNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.sparxsystems.com/profiles/GML/1.0"
  prefix_default "GML"
  element_form_default :qualified
end

class CityGmlNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.sparxsystems.com/profiles/CityGML/1.0"
  prefix_default "CityGML"
  element_form_default :qualified
end

class CgmlNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.sparxsystems.com/profiles/CGML/1.0"
  prefix_default "CGML"
  element_form_default :qualified
end

class TestingDuplicateNamespace < Lutaml::Model::XmlNamespace
  uri "https://testing-duplicate"
  prefix_default "td"
  element_form_default :qualified
end

class TestElementNamespace < Lutaml::Model::XmlNamespace
  uri "https://test-element"
  prefix_default "te"
  element_form_default :qualified
end

class ParentNamespace < Lutaml::Model::XmlNamespace
  uri "http://parent-namespace"
  prefix_default "pn"
  element_form_default :qualified
end

class ChildNamespace < Lutaml::Model::XmlNamespace
  uri "http://child-namespace"
  prefix_default "cn"
  element_form_default :qualified
end

class XsdNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.w3.org/2001/XMLSchema"
  prefix_default "xsd"
  element_form_default :qualified
end

# Namespace for default_namespace_spec.rb
class ExampleNamespaceDefault < Lutaml::Model::XmlNamespace
  uri "http://example.com/ns"
  # W3C default: :unqualified - children in blank namespace
  # Omit element_form_default to use W3C default behavior
end

# Namespace for mixed_content_spec.rb
class ExampleSchemaNamespace < Lutaml::Model::XmlNamespace
  uri "http://example.com/schema"
  prefix_default "xsd"
  element_form_default :qualified
end

# Namespaces for xml_adapter/xml_namespace_spec.rb
class TestNamespaceNoPrefix < Lutaml::Model::XmlNamespace
  uri "http://example.com/test"
  element_form_default :qualified
  # No prefix_default - will use default namespace format
end

class TestNamespace < Lutaml::Model::XmlNamespace
  uri "http://example.com/test"
  prefix_default "test"
  element_form_default :qualified
end

class FooNamespace < Lutaml::Model::XmlNamespace
  uri "http://example.com/foo"
  prefix_default "foo"
  element_form_default :qualified
end

class XmlLangNamespace < Lutaml::Model::XmlNamespace
  uri "http://example.com/xml"
  prefix_default "xml"
  element_form_default :qualified
end

class BarNamespace < Lutaml::Model::XmlNamespace
  uri "http://example.com/bar"
  prefix_default "bar"
  element_form_default :qualified
end

class BazNamespace < Lutaml::Model::XmlNamespace
  uri "http://example.com/baz"
  prefix_default "baz"
  element_form_default :qualified
end

class TestSchemasNamespace < Lutaml::Model::XmlNamespace
  uri "http://www.test.com/schemas/test/1.0/"
  prefix_default "test"
  element_form_default :qualified
end

class UnitsNamespace < Lutaml::Model::XmlNamespace
  uri "https://schema.example.org/units/1.0"
  element_form_default :qualified
end

# Namespace for namespace_spec.rb
class AbcNamespace < Lutaml::Model::XmlNamespace
  uri "https://abc.com"
  element_form_default :qualified
end

# Namespace for xml/namespace/nested_with_explicit_namespace_spec.rb
class TestBaseNamespace < Lutaml::Model::XmlNamespace
  uri "https://test-namespace"
  prefix_default "test"
  element_form_default :qualified
end
