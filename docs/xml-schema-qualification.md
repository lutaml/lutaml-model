If the namespace of child is different from parent, then the child can ALSO
define its own default namespace to indicate its namespace.

Furthermore, we need to clarify the case with qualified and unqualifieid XML
elements. Remember that unqualified vs qualifieid is ONLY for the TOP LEVEL
ELEMENTs.

Important to note that "qualified" vs "unqualified" does not have ANYTHING to
do with the prefix being present or not.

What it has to do is "qualified" means the ELEMENT/ATTRIBUTE needs a namespace
declared in the XML, "unqualified" means the ELEMENT/ATTRIBUTE does not need a
namespace declared in the XML (i.e. we look to its parent's namespace to find
its namespace).

When there is no XML Schema present:
* element "acts like" unqualified (because of default namespace inheritance, does not need prefix)
* attribute "acts like" qualified (because of no default namespace inheritance, requires prefix)

When there is an XML Schema present:
* element is unqualified
* attribute is unqualified

Notice that in default namespace inheritance:
* child element inherits default namespace
* attributes DO NOT INHERIT any namespace


NOTE: This is messed up but reflective of standards.

There are these cases:

1. No namespace

```xml
<list>
  <item>hi</item>
</list>
```

Here list and item have no namespace declared, so both have the blank
namespace.

2. parent has default namespace

```xml
<list xmlns="example">
  <item>hi</item>
</list>
```

Here `<list>` is qualified with a default namespace, and `<item>` is also
qualified by nature that it obtains the default namespace from the `xmlns=""`
statement.  This is because of how default namespace inheritance works.

Then both list and item have the same namespace of "example".


3. parent has prefixed namespace

```xml
<!-- no schema means element form is "qualified" -->
<ex:list xmlns:ex="example">
  <item>hi</item>
</ex:list>
```

Here `<list>` is qualified, but `<item>` is unqualified.

Here, the child `<item>` has blank namespace, but `<list>` has namesapce
"element".

4. If element form default is unqualified

Interestingly, if there is a schema, then the element/attribute form default is
"unqualified".

```xml
<!-- has schema but no settings means element form is "unqualified" -->
<ex:list xmlns:ex="example">
  <item>hi</item>
</ex:list>
```

Here, the child `<item>` has the same namespace as `<list>` with namesapce
"element", because "unqualified" means "my children do not need extra
qualification". If `<item>` contains other elements, they are ALSO considered
to be in the "element" namespace (unless overridden, of course).

5. If element form default is qualified

Then there are two cases:

The first case is same as no schema using default namespace:

```xml
<list xmlns="example">
  <item>hi</item>
</list>
```

Then both list and item have the same namespace of "example".

The second case is same as prefixed schema:

```xml
<ex:list xmlns:ex="example">
  <ex:item>hi</ex:item>
</ex:list>
```

Then both list and item have the same namespace of "example".

In this case, where it is qualified but the `<item>` is not
using the same prefix as the parent's namespace prefix, then
`<item>` is in a blank namespace. Contrast this case with
"unqualified".

```xml
<ex:list xmlns:ex="example">
  <item>hi</item>
</ex:list>
```

6. Notice that attribute handling is slightly different
because default namespace inheritance only applies to elements.

```xml
<list xmlns="example">
  <item attr="hello">hi</item>
</list>
```

Here, the elements `<list>` and `<item>` both belong to namespace
"example", but attribute `attr` belongs to the blank namespace.

This setup indicates that in terms of qualification:
* the elements `<list>` and `<item>` are both qualified (because they have a
  namespace)
* the attribute `attr` is unqualified

This means that if we want to place `attr` in the "example" namespace and if we
cannot change this instance, then we set a schema with:
* element: qualified
* attribute: unqualified

Then this puts `attr` into the same namespace in terms of the schema.

In this case:
```xml
<list xmlns="example" xmlns:egg="example">
  <item egg:attr="hello">hi</item>
</list>
```

This setup indicates that in terms of qualification:
* the elements `<list>` and `<item>` are both qualified (because they have a
  namespace)
* the attribute `attr` is qualified because its namespace
  comes from the prefixed namespace.

Then the schema will consider these all 3 to be in the same
namespace for validation.

---

You need to write this down (and elaborate any further examples if gaps exist)
on disk as an introduction to XML element and attribute namespace and schema
validation guide.


