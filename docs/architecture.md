# LutaML Model Architecture

This document describes the architecture of the LutaML Model library, focusing on the type resolution system and global state management introduced in version 0.7+.

## Overview

LutaML Model provides a declarative DSL for defining data models that can be serialized to and from multiple formats (XML, JSON, YAML, TOML).

### Key Design Principles

1. **Object-Oriented Design**: Each class has a single responsibility
2. **MECE (Mutually Exclusive, Collectively Exhaustive)**: Clear separation of concerns
3. **Open/Closed Principle**: Open for extension, closed for modification
4. **Immutability**: Value objects for type substitution rules

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           GlobalContext                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐     │
│  │ ContextRegistry │  │ CachedType      │  │ ImportRegistry      │     │
│  │                 │  │ Resolver        │  │                     │     │
│  │ :default ──────►│  │                 │  │ Deferred imports    │     │
│  │ :my_app ───────►│  │ Wraps Type      │  │ Explicit resolution │     │
│  │                 │  │ Resolver        │  │                     │     │
│  └────────┬────────┘  └────────┬────────┘  └─────────────────────┘     │
│           │                    │                                        │
│           ▼                    ▼                                        │
│  ┌─────────────────┐  ┌─────────────────┐                              │
│  │ TypeContext     │  │ TypeResolver    │                              │
│  │                 │  │                 │                              │
│  │ - registry      │  │ Stateless       │                              │
│  │ - substitutions │  │ resolution      │                              │
│  │ - fallbacks     │  │ logic           │                              │
│  └────────┬────────┘  └─────────────────┘                              │
│           │                                                             │
│           ▼                                                             │
│  ┌─────────────────┐                                                   │
│  │ TypeRegistry    │                                                   │
│  │                 │                                                   │
│  │ Symbol → Class  │                                                   │
│  │ mappings        │                                                   │
│  └─────────────────┘                                                   │
└─────────────────────────────────────────────────────────────────────────┘
```

## Core Components

### TypeRegistry

**Responsibility**: Pure data store for type mappings.

```ruby
registry = Lutaml::Model::TypeRegistry.new
registry.register(:string, Lutaml::Model::Type::String)
registry.register(:integer, Lutaml::Model::Type::Integer)

registry.lookup(:string)  #=> Lutaml::Model::Type::String
registry.registered?(:string)  #=> true
```

**Key characteristics:**
- No resolution logic
- No fallbacks
- No caching
- Just Symbol → Class mappings

### TypeContext

**Responsibility**: Bundles all context needed for type resolution.

```ruby
context = Lutaml::Model::TypeContext.new(
  registry: my_registry,
  substitutions: [
    Lutaml::Model::TypeSubstitution.new(from_type: OldType, to_type: NewType)
  ],
  fallbacks: [default_context]
)
```

**Factory methods:**
- `TypeContext.default` - Creates context with builtin types
- `TypeContext.isolated` - Creates empty context
- `TypeContext.derived(from:, with_substitutions:)` - Creates derived context

### TypeResolver

**Responsibility**: Stateless type resolution logic.

```ruby
resolver = Lutaml::Model::TypeResolver

# Resolve a type name to a class
type_class = resolver.resolve(:string, context)

# Check if resolvable
resolver.resolvable?(:string, context)  #=> true
```

**Resolution chain:**
1. Check if name is already a Class (pass-through)
2. Look up in primary registry
3. Apply type substitutions
4. Check fallback contexts
5. Raise UnknownTypeError if not found

### CachedTypeResolver

**Responsibility**: Decorator that adds thread-safe caching.

```ruby
cached_resolver = Lutaml::Model::CachedTypeResolver.new(delegate: TypeResolver)
cached_resolver.resolve(:string, context)  # Resolves and caches
cached_resolver.resolve(:string, context)  # Returns cached value
```

**Thread safety**: Uses Mutex for concurrent access.

### TypeSubstitution

**Responsibility**: Immutable value object for type substitution rules.

```ruby
substitution = Lutaml::Model::TypeSubstitution.new(
  from_type: Lutaml::Model::Type::DateTime,
  to_type: Lutaml::Model::Type::DateTimeWithPrecision
)

substitution.applies_to?(Lutaml::Model::Type::DateTime)  #=> true
substitution.apply(Lutaml::Model::Type::DateTime)  #=> DateTimeWithPrecision
```

### GlobalContext

**Responsibility**: Single entry point for all mutable global state.

```ruby
# Access the singleton
Lutaml::Model::GlobalContext.registry
Lutaml::Model::GlobalContext.resolver
Lutaml::Model::GlobalContext.imports

# Resolve types
Lutaml::Model::GlobalContext.resolve_type(:string)

# Create custom contexts
Lutaml::Model::GlobalContext.create_context(id: :my_app)

# Use custom context
Lutaml::Model::GlobalContext.with_context(:my_app) do
  # Code here uses :my_app as default context
end

# Reset for testing
Lutaml::Model::GlobalContext.reset!
```

### ImportRegistry

**Responsibility**: Deferred import management with explicit resolution.

```ruby
imports = Lutaml::Model::ImportRegistry.new

# Defer an import
imports.defer(MyClass, method: :import_model, symbol: :OtherModel)

# Check pending status
imports.pending?(MyClass)  #=> true

# Resolve all pending imports
imports.resolve(MyClass, context)

# Get pending classes
imports.pending_classes  #=> [MyClass, OtherClass]
```

### ContextRegistry

**Responsibility**: Named context store.

```ruby
registry = Lutaml::Model::ContextRegistry.new
registry.register(context)
registry.lookup(:my_app)
registry.unregister(:my_app)
registry.context_ids  #=> [:default, :my_app]
```

## Migration Guide

### From Register to GlobalContext

**Before (deprecated):**
```ruby
# Create a register
register = Lutaml::Model::Register.new(:my_app)

# Register a class
register.register_class(MyClass, :my_class)

# Look up a class
klass = register.get_class_without_register(:my_class)

# Clear caches
Lutaml::Model::GlobalRegister.instance.clear_all_model_caches
```

**After (recommended):**
```ruby
# Create a context
context = Lutaml::Model::GlobalContext.create_context(
  id: :my_app,
  registry: Lutaml::Model::TypeRegistry.new
)

# Register a type
context.registry.register(:my_class, MyClass)

# Resolve a type
klass = Lutaml::Model::GlobalContext.resolve_type(:my_class, :my_app)

# Clear caches
Lutaml::Model::GlobalContext.reset!
```

### Test Isolation

**Before (complex):**
```ruby
config.before do
  Lutaml::Model::GlobalRegister.instance.reset
  Lutaml::Model::GlobalRegister.clear_all_model_caches
  Lutaml::Model::TransformationRegistry.instance.clear
  # Still leaves caches on every Attribute!
end

config.after do
  CustomClass.clear_cache if CustomClass.respond_to?(:clear_cache)
end
```

**After (recommended):**
```ruby
config.before do
  Lutaml::Model::GlobalContext.clear_caches
  Lutaml::Model::TransformationRegistry.instance.clear
  Lutaml::Model::GlobalRegister.instance.reset
end
```

Note: `GlobalContext.reset!` removes all registered types and should only be
used for full teardown, not per-test isolation. Use `clear_caches` to reset
caches while preserving registered types.

## SOLID Principles Compliance

### Single Responsibility Principle (SRP)

Each class has one reason to change:

| Class | Responsibility |
|-------|---------------|
| TypeRegistry | Store type mappings |
| TypeContext | Bundle resolution context |
| TypeResolver | Resolve types |
| CachedTypeResolver | Add caching |
| GlobalContext | Entry point for global state |
| ImportRegistry | Manage deferred imports |

### Open/Closed Principle (OCP)

- **Open for extension**: New TypeContexts can be created without modifying existing code
- **Closed for modification**: TypeResolver doesn't need changes for new type sources

### Liskov Substitution Principle (LSP)

- CachedTypeResolver can substitute TypeResolver anywhere
- TypeContext subclasses (if any) would be substitutable

### Interface Segregation Principle (ISP)

- TypeContext only includes what's needed for resolution
- ImportRegistry has a focused API for import management

### Dependency Inversion Principle (DIP)

- High-level modules (GlobalContext) depend on abstractions
- Concrete implementations can be swapped (e.g., CachedTypeResolver wraps TypeResolver)

## Best Practices

### 1. Use GlobalContext for test isolation

```ruby
# In spec_helper.rb
config.before do
  Lutaml::Model::GlobalContext.clear_caches
  Lutaml::Model::TransformationRegistry.instance.clear
  Lutaml::Model::GlobalRegister.instance.reset
end
```

### 2. Create isolated contexts for complex applications

```ruby
context = GlobalContext.create_context(
  id: :my_app,
  substitutions: [
    TypeSubstitution.new(from_type: DateTime, to_type: PreciseDateTime)
  ]
)
```

### 3. Use with_context for thread-safe context switching

```ruby
GlobalContext.with_context(:my_app) do
  # All type resolution uses :my_app context
  result = MyModel.from_json(data)
end
```

### 4. Avoid respond_to? for interface detection

```ruby
# BAD (duck typing)
if klass.respond_to?(:attributes)
  klass.attributes
end

# GOOD (explicit type check)
if klass.is_a?(Class) && klass.include?(Lutaml::Model::Serialize)
  klass.attributes
end
```

### 5. Use respond_to? only for valid patterns

```ruby
# GOOD: Cross-hierarchy capability check
if type_class.respond_to?(:xml_namespace)
  type_class.xml_namespace
end

# GOOD: Standard Ruby protocol
if value.respond_to?(:empty?) && value.empty?
  return
end
```

## Deprecated APIs

The following APIs are deprecated and will be removed in a future version:

| Deprecated API | Replacement |
|---------------|-------------|
| `Lutaml::Model::Register` | `Lutaml::Model::GlobalContext.create_context` |
| `Lutaml::Model::GlobalRegister` | `Lutaml::Model::GlobalContext` |
| `register.lookup_type(name)` | `GlobalContext.resolve_type(name, context_id)` |
| `GlobalRegister.instance.clear_all_model_caches` | `GlobalContext.reset!` |

## Troubleshooting

### UnknownTypeError

**Problem**: `Lutaml::Model::UnknownTypeError: Unknown type 'my_type'`

**Solution**: Register the type in a TypeRegistry:

```ruby
context = GlobalContext.create_context(
  id: :my_app,
  registry: TypeRegistry.new.tap { |r| r.register(:my_type, MyType) }
)
```

### Test Pollution

**Problem**: Tests fail with random seed but pass with ordered execution.

**Solution**: Ensure `GlobalContext.clear_caches` is called in test setup:

```ruby
config.before do
  Lutaml::Model::GlobalContext.clear_caches
  Lutaml::Model::TransformationRegistry.instance.clear
  Lutaml::Model::GlobalRegister.instance.reset
end
```

### Circular Import Detection

**Problem**: `ImportError: Circular import detected`

**Solution**: Use ImportRegistry to defer imports:

```ruby
# Instead of importing immediately
import_model :OtherModel

# Defer the import
GlobalContext.imports.defer(self, method: :import_model, symbol: :OtherModel)
```
