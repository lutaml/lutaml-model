# Namespace Options: MECE Specification

## Overview

This document defines the **mutually exclusive, collectively exhaustive (MECE)** namespace options for Lutaml::Model, distinguishing between **class-level** and **mapping-level** declarations.

## Critical Distinction: Class Level vs Mapping Level

### Class Level: "What namespace does this TYPE belong to?"

**Location**: In the model's `xml do` block

```ruby
class MyModel < Lutaml::Model::Serializable
  xml do
    element "model"
    namespace <value>  # ← CLASS LEVEL
  end
end
```

**Question Answered**: "What is the namespace identity of this model/type?"

### Mapping Level: "Where does THIS INSTANCE appear?"

**Location**: In `map_element`/`map_attribute` parameters

```ruby
xml do
  map_element "child", to: :child, namespace: <value>  # ← MAPPING LEVEL
end
```

**Question Answered**: "Should this instance use a different namespace than its type?"

## Class-Level Options (MECE)

### Option 1: `namespace NamespaceClass` - Explicit Namespace Identity

**Meaning**: This model/type belongs to the specified namespace

**Use Case**: Standard case - model has namespace identity

**Example**:
```ruby
class Person < Lutaml::Model::Serializable
  xml do
    element "person"
    namespace ContactNamespace  # This type belongs to ContactNamespace
  end
end
```

**Behavior**:
- Type has namespace identity
- Always serializes in this namespace (unless mapping overrides)
- Children decide whether to inherit based on form rules

### Option 2: `namespace "http://..."` - Inline URI

**Meaning**: This model/type belongs to inline URI namespace

**Use Case**: One-off namespace without creating XmlNamespace class

**Example**:
```ruby
xml do
  element "model"
  namespace "http://example.com/inline"  # Inline URI
end
```

**Behavior**: Same as Option 1, but namespace class created automatically

### Option 3: `namespace :blank` - Explicit Blank Namespace Identity

**Meaning**: This model/type explicitly has NO namespace identity

**Use Case**: Type that should NEVER have a namespace, even when used in namespaced context

**Example**:
```ruby
class LocalModel < Lutaml::Model::Serializable
  xml do
    element "local"
    namespace :blank  # This type has NO namespace
  end
end
```

**Behavior**:
- Type has blank namespace identity
- Never inherits from parent (even with elementFormDefault: :qualified)
- Generates `xmlns=""` when parent uses default namespace

### Option 4: Omit `namespace` - No Explicit Identity (Context-Dependent)

**Meaning**: This model/type has NO namespace identity, follows context rules

**Use Case**: Local declarations that inherit based on elementFormDefault

**Example**:
```ruby
class LocalElement < Lutaml::Model::Serializable
  xml do
    element "local"
    # No namespace declaration
  end
end
```

**Behavior**:
- Type has no namespace identity
- When used as child: follows elementFormDefault
- When used as root: blank namespace

### Option 5: `namespace nil` - PROPOSED: Same as Omitting

**Meaning**: Explicitly "not set" (same as omitting)

**Ruby Convention**: `nil` typically means "unset" or "use default"

**Recommendation**: Make `namespace nil` equivalent to omitting namespace

**Rationale**: 
- `nil` = "not set" is Ruby idiomatic
- `:blank` = "explicitly blank" is clearer
- Keeps options MECE

## MECE Analysis: Class Level

| Option | Has Identity? | Namespace | Inheritable? | Use Case |
|--------|--------------|-----------|--------------|----------|
| `NamespaceClass` | ✅ Yes | Specific URI | Via form rules | Standard |
| `"http://..."` | ✅ Yes | Inline URI | Via form rules | One-off |
| `:blank` | ✅ Yes | **Blank** | ❌ Never | Explicit no-namespace |
| Omit / `nil` | ❌ No | (context) | ✅ Yes | Local element |

**MECE Verification**:
- ✅ **Mutually Exclusive**: Each option has distinct behavior
- ✅ **Collectively Exhaustive**: All possible cases covered
- ✅ **Clear Semantics**: No ambiguity between options

## Mapping-Level Options (MECE)

At mapping level, we can **override** the class-level namespace.

### Option M1: `namespace: NamespaceClass` - Override to Specific

**Priority**: HIGHEST (overrides type identity and context)

**Use Case**: Type belongs to namespace A, but this instance should use namespace B

**Example**:
```ruby
class Address < Lutaml::Model::Serializable
  xml do
    namespace AddressNamespace  # Type identity
  end
end

class Person < Lutaml::Model::Serializable
  attribute :address, Address
  
  xml do
    namespace PersonNamespace
    # Override: address instance uses PersonNamespace, not AddressNamespace
    map_element "address", to: :address, namespace: PersonNamespace
  end
end
```

### Option M2: `namespace: :blank` - Override to Blank

**Priority**: HIGHEST (overrides type identity and context)

**Use Case**: Type has namespace, but this instance should have none

**Example**:
```ruby
class NamespacedType < Lutaml::Model::Serializable
  xml do
    namespace TypeNamespace  # Type has namespace
  end
end

class Parent < Lutaml::Model::Serializable
  attribute :child, NamespacedType
  
  xml do
    # Override: child instance has NO namespace despite type having one
    map_element "child", to: :child, namespace: :blank
  end
end
```

### Option M3: `namespace: :inherit` - Override to Parent's Namespace

**Priority**: HIGHEST (overrides type identity)

**Use Case**: Type has different namespace, but instance should use parent's

**Example**:
```ruby
class DifferentNsType < Lutaml::Model::Serializable
  xml do
    namespace TypeNamespace  # Different namespace
  end
end

class Parent < Lutaml::Model::Serializable
  attribute :child, DifferentNsType
  
  xml do
    namespace ParentNamespace
    # Override: child uses ParentNamespace, not TypeNamespace
    map_element "child", to: :child, namespace: :inherit
  end
end
```

### Option M4: `namespace: nil` / Omit - Don't Override

**Priority**: LOWEST (use type identity or context)

**Use Case**: Let type's namespace or context rules apply

**Example**:
```ruby
class Parent < Lutaml::Model::Serializable
  attribute :typed_child, TypedModel
  attribute :untyped_child, :string
  
  xml do
    # Uses type's namespace (if TypedModel has one)
    map_element "typed", to: :typed_child
    
    # Uses context rules (elementFormDefault)
    map_element "untyped", to: :untyped_child
  end
end
```

## MECE Analysis: Mapping Level

| Option | Override? | Final Namespace | Use Case |
|--------|-----------|----------------|----------|
| `NamespaceClass` | ✅ Yes | That class | Force specific |
| `:blank` | ✅ Yes | Blank | Force none |
| `:inherit` | ✅ Yes | Parent's | Force parent |
| `nil` / Omit | ❌ No | Type or context | Use defaults |

**MECE Verification**:
- ✅ **Mutually Exclusive**: Each override has different target
- ✅ **Collectively Exhaustive**: Covers all override scenarios
- ✅ **Priority Clear**: Override vs default is unambiguous

## Complete Resolution Algorithm (MECE)

### For Elements

**Priority Order** (first match wins):

```
1. Mapping namespace: NamespaceClass → Use that namespace
2. Mapping namespace: :blank → Blank namespace (xmlns="" if parent default)
3. Mapping namespace: :inherit → Parent's namespace (with parent's format)
4. Mapping namespace: nil/omitted → Continue ↓
5. Type xml_namespace set → Type's namespace
6. Type namespace: :blank → Blank namespace
7. Type namespace: omitted → Continue ↓
8. Class namespace: NamespaceClass → That namespace  
9. Class namespace: :blank → Blank namespace
10. Class namespace: nil/omitted → Continue ↓
11. form: :qualified → Parent's namespace
12. elementFormDefault: :qualified → Parent's namespace
13. form: :unqualified → Blank namespace
14. elementFormDefault: :unqualified → Blank namespace
15. Default → Blank namespace
```

### For Attributes

**Priority Order**:

```
1. Mapping namespace: NamespaceClass → Use that namespace
2. Mapping namespace: :blank → Blank namespace (no prefix)
3. Mapping namespace: nil/omitted → Continue ↓
4. Type xml_namespace set → Type's namespace
5. Type namespace: :blank → Blank namespace
6. Type namespace: omitted → Continue ↓
7. form: :qualified → Hosting element's namespace
8. attributeFormDefault: :qualified → Hosting element's namespace
9. form: :unqualified → Blank namespace
10. attributeFormDefault: :unqualified → Blank namespace (DEFAULT per W3C)
11. Default → Blank namespace
```

## Proposed `namespace nil` Semantics

**Question**: "Is `namespace nil` MECE with the rest?"

**Answer**: YES, if we define it clearly:

### Recommended Semantics

**At Class Level**:
- `namespace nil` = "not set" = same as omitting
- Equivalent to #10 in resolution (no namespace identity)

**At Mapping Level**:
- `namespace: nil` = "don't override" = same as omitting
- Equivalent to #4 in resolution (use type/context)

**At Type Level**:
- Not applicable (types either have xml_namespace or don't)

### Why This is MECE

| Scenario | Namespace Set? | Behavior |
|----------|---------------|----------|
| `namespace SomeNs` | ✅ Yes | Has identity |
| `namespace :blank` | ✅ Yes | Has blank identity |
| `namespace :inherit` | ✅ Yes | Inherit (mapping only) |
| `namespace nil` | ❌ No | Same as omit |
| Omit namespace | ❌ No | Use context |

**Mutual Exclusion**: Each "set" option has different meaning
**Collective Exhaustion**: "Not set" (nil/omit) is one case, all "set" cases covered

## Usage Matrix (Complete)

### Class Definition

```ruby
class Model < Lutaml::Model::Serializable
  xml do
    # Option 1: Specific namespace
    namespace ContactNamespace
    
    # Option 2: Inline URI  
    namespace "http://..."
    
    # Option 3: Explicit blank
    namespace :blank
    
    # Option 4: Not set (nil or omit)
    namespace nil
    # OR just omit it
  end
end
```

### Mapping Override

```ruby
xml do
  # Option M1: Override to specific
  map_element "child", to: :child, namespace: OtherNamespace
  
  # Option M2: Override to blank
  map_element "child", to: :child, namespace: :blank
  
  # Option M3: Override to inherit parent
  map_element "child", to: :child, namespace: :inherit
  
  # Option M4: Don't override (nil or omit)
  map_element "child", to: :child, namespace: nil
  # OR
  map_element "child", to: :child  # same as nil
end
```

### Type Declaration

```ruby
class MyType < Lutaml::Model::Type::String
  # Option T1: Type has namespace
  xml_namespace TypeNamespace
  
  # Option T2: Type has no namespace (omit)
  # Just don't call xml_namespace
end
```

**Note**: `:blank` and `:inherit` don't make sense at type level (types have identity or don't)

## Implementation Requirements

### Support Matrix

| Location | NamespaceClass | String URI | :blank | :inherit | nil/omit |
|----------|---------------|------------|--------|----------|----------|
| Class `namespace` | ✅ Yes | ✅ Yes | ✅ Need | ❌ No* | ✅ Yes |
| Mapping `namespace:` | ✅ Yes | ✅ Yes | ✅ Need | ✅ Yes | ✅ Yes |
| Type `xml_namespace` | ✅ Yes | ❌ No | ❌ No | ❌ No | ❌ N/A |

*`:inherit` doesn't make sense at class level (class can't inherit from parent)

### Validation Rules

**Class Level**:
```ruby
def namespace(value, prefix = nil)
  case value
  when Class then accept if < XmlNamespace
  when String then create anonymous XmlNamespace
  when :blank then set to blank namespace identity
  when :inherit then ERROR "Use :inherit at mapping level only"
  when nil then same as omit (not set)
  else ERROR "Invalid namespace value"
  end
end
```

**Mapping Level**:
```ruby
def map_element(name, to:, namespace: nil, ...)
  case namespace
  when Class then override to that namespace
  when String then override to inline URI
  when :blank then override to blank namespace
  when :inherit then override to parent's namespace
  when nil then don't override (use type/context)
  else ERROR "Invalid namespace value"
  end
end
```

## Semantic Clarity: namespace nil

### Proposed Unified Semantics

**`namespace nil` everywhere means**: "Not set, use default behavior"

**At Class Level**:
```ruby
namespace nil
# Equivalent to omitting namespace
# Model has no namespace identity
# Behavior determined by context when used
```

**At Mapping Level**:
```ruby
map_element "child", to: :child, namespace: nil
# Equivalent to omitting namespace: parameter
# Don't override, use type's namespace or context
```

**MECE Impact**: 
-  `nil` is in the "not set" category
- `:blank` is in the "set to blank" category
- **Mutually exclusive**: nil ≠ :blank
- **Collectively exhaustive**: All cases covered

## Recommended API

### Class-Level API

```ruby
class Model < Lutaml::Model::Serializable
  xml do
    element "model"
    
    # VALID OPTIONS:
    namespace MyNamespace      # Explicit namespace
    namespace "http://..."     # Inline URI
    namespace :blank           # Explicit blank namespace
    namespace nil              # Not set (same as omit)
    # OR omit namespace entirely
    
    # INVALID OPTION:
    namespace :inherit         # ERROR: Can't inherit at class level
  end
end
```

**Error Messages**:
```ruby
namespace :inherit  
# → ArgumentError: "Use :inherit at mapping level only. 
#    At class level, use specific namespace or omit."
```

### Mapping-Level API

```ruby
xml do
  # VALID OPTIONS:
  map_element "e", to: :e, namespace: OtherNamespace  # Override to specific
  map_element "e", to: :e, namespace: "http://..."    # Override to inline URI
  map_element "e", to: :e, namespace: :blank          # Override to blank
  map_element "e", to: :e, namespace: :inherit        # Override to parent
  map_element "e", to: :e, namespace: nil             # Don't override
  map_element "e", to: :e                             # Same as nil
end
```

### Type-Level API

```ruby
class MyType < Lutaml::Model::Type::Value
  # VALID OPTIONS:
  xml_namespace TypeNamespace   # Type has namespace identity
  # OR omit (type has no namespace)
  
  # INVALID OPTIONS:
  xml_namespace :blank    # ERROR: Just omit if no namespace
  xml_namespace :inherit  # ERROR: Types have identity, can't inherit
  xml_namespace nil       # ERROR: Just omit
end
```

**Rationale**: Types either have namespace identity (class) or don't (omit). Symbols don't make sense.

## Complete MECE Truth Table

### Class Level Namespace Options

| Value | Set? | Identity | Context-Dependent? | Valid? |
|-------|------|----------|-------------------|--------|
| `NamespaceClass` | ✅ | That namespace | ❌ No | ✅ Yes |
| `"http://..."` | ✅ | Inline URI | ❌ No | ✅ Yes |
| `:blank` | ✅ | Blank | ❌ No | ✅ Yes |
| `:inherit` | N/A | N/A | N/A | ❌ **ERROR** |
| `nil` | ❌ | None | ✅ Yes | ✅ Yes (=omit) |
| Omit | ❌ | None | ✅ Yes | ✅ Yes |

### Mapping Level Namespace Options

| Value | Override? | Target | Valid? |
|-------|-----------|--------|--------|
| `NamespaceClass` | ✅ | That namespace | ✅ Yes |
| `"http://..."` | ✅ | Inline URI | ✅ Yes |
| `:blank` | ✅ | Blank | ✅ Yes |
| `:inherit` | ✅ | Parent's ns | ✅ Yes |
| `nil` | ❌ | (type/context) | ✅ Yes (=omit) |
| Omit | ❌ | (type/context) | ✅ Yes |

### Type Level xml_namespace Options

| Value | Valid? | Recommendation |
|-------|--------|----------------|
| `NamespaceClass` | ✅ Yes | Standard case |
| Any other value | ❌ No | Just omit |

## Implementation Checklist

### Validation

- [ ] Class `namespace`: Accept Class, String, :blank, nil
- [ ] Class `namespace`: Reject :inherit with clear error
- [ ] Mapping `namespace:`: Accept Class, String, :blank, :inherit, nil
- [ ] Type `xml_namespace`: Accept only Class or omit
- [ ] Type `xml_namespace`: Reject :blank, :inherit, nil with error

### Behavior

- [ ] `namespace nil` ≡ omit at class level
- [ ] `namespace: nil` ≡ omit at mapping level
- [ ] `namespace :blank` → explicit blank identity
- [ ] `namespace: :blank` → explicit blank override
- [ ] `namespace :inherit` → ERROR at class level
- [ ] `namespace: :inherit` → parent namespace at mapping level

### Edge Cases

- [ ] `namespace nil` after inheriting from parent with namespace → removes it
- [ ] `namespace :blank` vs omit → both work, :blank is explicit
- [ ] `:inherit` in nested mappings → uses immediate parent
- [ ] `:blank` generates xmlns="" only when parent uses default format

## Documentation Requirements

### User Guide Additions

**Section**: "Namespace Value Options"

**Content**:
```adoc
=== Namespace value options

==== At class level

`namespace NamespaceClass`::
Model belongs to specific namespace

`namespace "http://..."`::
Model belongs to inline URI namespace

`namespace :blank`::
Model explicitly has blank namespace (never inherits)

`namespace nil` or omit::
Model has no namespace identity (context-dependent)

==== At mapping level

`namespace: NamespaceClass`::
Override to specific namespace

`namespace: :blank`::
Override to blank namespace

`namespace: :inherit`::
Override to parent's namespace

`namespace: nil` or omit::
Don't override (use type or context)
```

### Error Messages

```ruby
# Class level
namespace :inherit
# → "ArgumentError: :inherit is only valid at mapping level (map_element/map_attribute).
#    At class level use specific namespace or omit to make context-dependent."

# Type level
xml_namespace :blank
# → "ArgumentError: Type namespaces must be XmlNamespace classes.
#    Omit xml_namespace if type has no namespace identity."
```

## Summary: MECE Namespace System

**Three Locations**:
1. Class level - Type identity
2. Mapping level - Instance override
3. Type level - Value type identity

**Four Semantic Options** (MECE):
1. **Specific** (Class/String) - Has definite namespace
2. **Blank** (:blank) - Has NO namespace (explicit)
3. **Inherit** (:inherit) - Use parent (mapping only)
4. **Unset** (nil/omit) - Context-dependent

**Key Insight**: `:blank` and `nil`/omit are DIFFERENT:
- `:blank` = "I definitely have NO namespace"
- `nil`/omit = "I have no opinion, use context"

This creates a clean, MECE system that handles all W3C scenarios.

---

**Status**: DESIGN FINALIZED
**Next**: Implement according to CONTINUATION_PLAN_FINAL_W3C_COMPLIANCE.md