---
title: "When GraphQL Normalization Does Not Preserve Validation"
date: 2026-08-01 00:00:00 -0700
description: "Why semantics-preserving GraphQL normalization can produce an invalid operation, and what Lean proofs reveal about validation and execution."
tags:
  - GraphQL
  - Lean
  - Formal methods
  - Query languages
---

<!-- cspell:words BoolCase Díaz Formedness Hartig nonemptiness Olmedo Pérez Tanter -->

In [the previous post]({% post_url 2026-08-01-formalizing-graphql-normalization %}),
I described a Lean formalization of GraphQL execution and a query normalizer
proved to preserve semantics. There is a qualification that deserves its own
post:

> Normalization does not preserve GraphQL validation unconditionally.

A valid source operation can normalize to an operation that fails validation,
even though the original and normalized operations still produce the same
response.

That sounds contradictory only if validity and meaning are the same property.
They are not. GraphQL validation checks a collection of mostly local syntactic
and type-system conditions. Execution interprets the whole operation against a
concrete runtime object and a concrete assignment of directive variables.
Normalization moves information between those levels. In doing so, it can make
an execution-time impossibility syntactically visible.

## Three different claims

It helps to separate three properties of a normalizer `N`:

1. **Normality:** `N(q)` has the intended normal-form syntactic shape.
2. **Semantic preservation:** `q` and `N(q)` produce equivalent responses.
3. **Validity preservation:** if `q` passes GraphQL validation, so does `N(q)`.

The first two do not imply the third. My semantic-preservation theorem does not
need the extra assumptions discussed below. The validity-preservation theorem
does.

Here is the Lean statement for complete, directive-aware normalization:

```lean
def completeNormalizeOperationValid (schema : Schema) (operation : Operation) : Prop :=
  SchemaWellFormedness.schemaWellFormed schema
  -> Validation.operationDefinitionValid schema operation
  -> operationFieldsValidInPossibleTypes schema operation
  -> operationBoolTypeConditionFeasible schema operation
  -> Validation.operationDefinitionValid schema
      (completeNormalizeOperation schema operation)
```

The first two premises are expected: the schema and source operation must be
valid. The other two are not GraphQL validation rules. They state the additional
conditions under which normalization preserves validation:

- every selected field remains valid in every concrete object type introduced
  by grounding; and
- every complete Boolean case and full stack of type conditions that the
  operation relies on is feasible.

Why are those conditions necessary?

## A nonempty selection set with no possible field

GraphQL rejects an empty selection set. But a syntactically nonempty selection
set can be *semantically* empty: every selection in it can be impossible for the
runtime object.

Consider this schema:

```graphql
interface I {
  id: ID
}

type A implements I {
  id: ID
}

type B implements I {
  id: ID
  data: String
}

type Query {
  f: A
}
```

And this operation:

```graphql
{
  f {
    ... on I {
      ... on B {
        data
      }
    }
  }
}
```

The operation passes the specification's
[fragment-spread applicability rule](https://spec.graphql.org/September2025/#sec-Fragment-Spread-Is-Possible).
That rule checks each fragment against its immediate parent scope:

- `A` overlaps `I`, because `A` implements `I`;
- `I` overlaps `B`, because `B` implements `I`.

Each step is possible locally. The complete path is not. No concrete object can
be both `A` and `B`, so the intersection of the stack `A`, `I`, and `B` is empty.

If `f` resolves to an `A`, execution enters the `I` fragment, rejects the nested
`B` condition, and collects no fields below `f`. The response can therefore be:

```json
{
  "data": {
    "f": {}
  }
}
```

Ground-type normalization makes the concrete runtime scope explicit and drops
the infeasible `B` path. What remains has the shape:

```graphql
{
  f {
  }
}
```

The empty object is the correct execution result, but the empty selection set is
not a valid GraphQL operation. Normalization did not introduce a semantic bug;
it exposed a global impossibility that pairwise validation had admitted.

The Lean predicate `typeConditionStackFeasible` states the missing global
condition directly:

```lean
def typeConditionStackFeasible (schema : Schema) (typeConditions : List Name) : Prop :=
  ∃ objectType,
    ∀ typeCondition,
      typeCondition ∈ typeConditions -> objectType ∈ schema.getPossibleTypes typeCondition
```

There must be at least one concrete object type belonging to every type
condition in the stack. Pairwise overlap is not enough.

## Directives create the same boundary

The built-in `@skip` and `@include` directives can also make a nonempty selection
set semantically empty. For example:

```graphql
type Payload {
  data: String
}

type Query {
  f: Payload!
}
```

```graphql
query Example($show: Boolean!) {
  f {
    data @include(if: $show)
  }
}
```

The operation is valid. When `$show` is `false`, however, field collection skips
`data`, and execution still produces the object field `"f": {}`.

Complete normalization enumerates Boolean assignments. In the false case it
must preserve that empty object; omitting `f` would change the response shape.
Once again, semantic preservation and GraphQL validity pull in different
directions: the semantically faithful branch contains an empty child selection
set.

`operationBoolTypeConditionFeasible` rules out that situation for the validity
theorem. It is path-sensitive and case-sensitive. Informally, it requires:

- every selection to survive in at least one complete Boolean case compatible
  with its ancestors;
- every full stack of type conditions on that path to have a possible concrete
  object; and
- whenever a composite selection survives in a Boolean case, at least one of
  its children to survive in that case.

This condition also protects GraphQL's
[all-variables-used rule](https://spec.graphql.org/September2025/#sec-All-Variables-Used).
If normalization removed every path containing a variable use, a previously
used variable could become unused. Feasibility supplies a surviving branch for
each source use. Directive variables remain present in the generated Boolean
case wrappers; other variables remain in at least one surviving selection.

## A field can be valid for an interface but not its implementation

The other validity gap comes from grounding fields selected under abstract
types. Consider:

```graphql
interface I {
  value(x: Int! = 7): String
}

type T implements I {
  value(x: Int!): String
}

type Query {
  i: I
}
```

The implementing field has the same argument type, but not the interface's
default value. This operation is valid when checked against the interface:

```graphql
{
  i {
    value
  }
}
```

Under `I.value`, argument `x` is optional because it has a default. But if `i`
resolves to a `T`, execution uses the concrete field definition `T.value`, where
`x` is non-null and has no default. Argument coercion then reports a missing
required argument before calling the resolver. Thus, if `i` resolves to a `T`,
execution reports an error even though validation succeeded.

Ground normalization turns the implicit possible runtime type into explicit
syntax:

```graphql
{
  i {
    ... on T {
      value
    }
  }
}
```

Now `value` is validated in the `T` scope, so the missing argument is visible to
the ordinary
[required-arguments rule](https://spec.graphql.org/September2025/#sec-Required-Arguments).
The normalized operation fails validation even though the source operation
passed.

This is the same mismatch described by GraphQL specification
[issue #1121](https://github.com/graphql/graphql-spec/issues/1121): validation
consults the abstract field definition, while execution can consult a concrete
implementation whose argument defaults differ.

The Lean assumption `operationFieldsValidInPossibleTypes` takes the
operation-local version of one proposed remedy. It recursively checks selected
fields in every possible concrete object scope that normalization may produce.
It is not part of `Validation.operationDefinitionValid`, because the current
GraphQL specification does not require it.

## What the proof found

The theorem-proving difficulty was useful evidence. A tempting statement was:

```text
valid(q) -> valid(N(q))
```

It is false. The failed proof obligations separate the reasons:

- local fragment applicability does not imply feasibility of a complete nested
  type-condition path;
- syntactic nonemptiness does not imply that a field survives execution under
  every Boolean assignment;
- validity under an abstract field definition does not imply validity under all
  concrete runtime types; and
- removing infeasible selections can remove the only use of a declared
  variable.

The corrected theorem makes those boundaries explicit instead of quietly
strengthening the definition of GraphQL validation.

This distinction matters for implementations. A normalizer used only as an
internal execution representation may permit empty selection sets while still
preserving responses. A tool that emits normalized GraphQL source must either
reject operations outside the theorem's domain, strengthen its validation, or
choose a representation that can express the empty-object behavior without
pretending the result is an ordinary valid operation.

Formalization did not merely confirm that the normalizer works. It identified
where GraphQL's validation abstraction stops matching its execution semantics,
and it turned that gap into two precise, reviewable assumptions.

## What should the GraphQL specification do?

The proof identifies the boundary, but it does not dictate one specification
change. There are at least two separate design questions.

### Should GraphQL allow empty selection sets?

The current
[selection-set grammar](https://spec.graphql.org/September2025/#sec-Selection-Sets)
requires at least one selection. Allowing an empty set would therefore be a
grammar change, not merely a relaxed validation rule.

There is a semantic argument for the change. Directives and infeasible type
conditions can already make a syntactically nonempty selection set collect no
fields at runtime. Query optimizers can expose the same state by deleting every
infeasible selection. If their output must remain valid GraphQL source, they
have to retain or invent a benign no-op selection such as
`__typename @include(if: false)`.

One option is to admit an empty selection set with the natural execution result:
an empty response object. Tooling could then lint both explicitly empty sets and
nonempty sets whose selections are all semantically infeasible. The conservative
alternative is to keep the source grammar unchanged and permit empty selection
sets only in runtime validators. Either choice should be
explicit; syntactic nonemptiness does not guarantee semantic nonemptiness.

### Fix issue #1121

[Issue #1121](https://github.com/graphql/graphql-spec/issues/1121) identifies
two places where the interface-default mismatch could be repaired. Schema
validation could forbid defaults on interface fields or require implementing
fields to preserve them. Alternatively, operation validation could check
required arguments against every possible runtime object type.

The Lean assumption `operationFieldsValidInPossibleTypes` models the latter,
operation-local approach. It requires every selected field to remain valid in
each concrete scope introduced by normalization. This leaves the schema rules
unchanged, but it rejects operations that currently validate and can produce an
argument error only at the time of execution.

The definitions and proofs are in
[`GraphQL/Theories/NormalForm.lean`](https://github.com/duckki/graphql-lean/blob/main/GraphQL/Theories/NormalForm.lean),
[`Proofs/GraphQL/Theories/NormalForm/CompleteNormalization`](https://github.com/duckki/graphql-lean/tree/main/Proofs/GraphQL/Theories/NormalForm/CompleteNormalization),
and the project's
[normal-form documentation](https://github.com/duckki/graphql-lean/blob/main/docs/normal-form.md).
