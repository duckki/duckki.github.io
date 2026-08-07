---
title: "Executing GraphQL Without CollectFields"
date: 2026-08-06 00:00:00 -0700
description: "A verified syntax-order GraphQL executor that avoids grouped field maps, plus a TypeScript implementation and benchmark against GraphQL.js."
tags:
  - GraphQL
  - Lean
  - TypeScript
  - Performance
---

<!-- cspell:words Formedness GraphQLConf Leia subselection subselections unflattened Zeng -->

In [the first post in this series]({% post_url
2026-08-01-formalizing-graphql-normalization %}), I described a spec-conformant GraphQL
executor formalized in Lean. That model also makes it possible to ask whether an
alternative execution algorithm preserves the specification's observable behavior.

The GraphQL specification executes a selection set in two phases. First,
[`CollectFields`](https://spec.graphql.org/September2025/#sec-Field-Collection)
walks selections and builds a map from each response name to all of
its matching field nodes. Then the executor resolves one field group at a time.

That structure ensures that each response position is resolved once, exposes all sibling
work before execution for async scheduling, and carries one visited-fragment set through
each collection scope. But the grouped map must be allocated. Large, fragment-heavy
operations can make field collection itself significant work. Could an executor instead
visit selections in syntax order, write fields directly into the response, and never
construct the map?

I modeled that alternative in Lean and proved that it preserves response data
and the presence of errors. I then built
[`graphql-ungrouped-js`](https://github.com/duckki/graphql-ungrouped-js), a
TypeScript implementation on top of GraphQL.js, to find out how this lighter
execution implementation performs in practice.

The answer is encouraging for synchronous execution. In one run of a synthetic,
selection-heavy benchmark, the latest implementation was up to 1.76× faster and used
28.6% less observed heap than GraphQL.js.

## What field collection buys

Consider two selections with the same response name:

```graphql
{
  hero {
    name
  }
  hero {
    friends {
      name
    }
  }
}
```

Conceptually, field collection turns the two child selection sets into this
merged in-memory view:

```graphql
{
  hero {
    name
    friends {
      name
    }
  }
}
```

This is not a rewrite of the query document. `CollectFields` retains both
`hero` nodes as one ordered field set, resolves `hero` once, and executes their
combined child selections against the same resolved object.

Field collection therefore does more than remove duplicates. It establishes
three useful properties before resolution begins:

- every occurrence with the same response name is available as one group;
- the field resolver runs once for that response position; and
- all child selection sets are merged before recursive execution.

The cost is that execution first walks the selection tree to create ordered maps
and field-node groups, then walks the grouped structure to resolve it. The
specification deliberately describes this behavior using a
[`collectedFieldsMap`](https://spec.graphql.org/September2025/#sec-Executing-the-Root-Selection-Set).
An implementation may optimize the representation, but it still has to preserve
the observable execution rules.

## Execute first, merge later

Ungrouped execution reverses the timing. It walks the original selection list
and updates the response as it goes:

1. On the first visit to a response name, resolve and complete the field.
2. If a later occurrence selects the same leaf field, keep the completed value.
3. If a later occurrence adds child selections to a composite field, reuse the
   first resolved source and complete only the new child selections.
4. Merge the newly completed child data into the existing response position.

Here is the same query annotated with the completion order:

```graphql
{
  # 1. Resolve hero and begin its response position.
  hero {
    # 2. Complete the first child response slice.
    name
  }
  # 3. Reuse hero's resolved source.
  hero {
    # 4. Complete and merge the second child response slice.
    friends {
      name
    }
  }
}
```

The two execution shapes differ in where they merge the child selections, but
converge on the same response:

<figure class="execution-flow">
  <div
    class="execution-flow__diagram"
    role="img"
    aria-label="An input query follows either collected or ungrouped execution. Collected execution merges child selections before completing one child response. Ungrouped execution completes two response slices and merges them afterward. Both produce the same hero response."
  >
    <div class="execution-flow__node execution-flow__input">Input query</div>
    <div class="execution-flow__branches">
      <section class="execution-flow__lane execution-flow__lane--collected">
        <div class="execution-flow__lane-title">Collected execution</div>
        <div class="execution-flow__node">
          Merge child selection sets<br><span>in memory</span>
        </div>
        <div class="execution-flow__arrow" aria-hidden="true">↓</div>
        <div class="execution-flow__node">Complete one child response</div>
      </section>
      <section class="execution-flow__lane execution-flow__lane--ungrouped">
        <div class="execution-flow__lane-title">Ungrouped execution</div>
        <div class="execution-flow__node">Complete <code>{ name }</code> slice</div>
        <div class="execution-flow__arrow" aria-hidden="true">↓</div>
        <div class="execution-flow__node">
          Complete <code>{ friends { name } }</code> slice
        </div>
        <div class="execution-flow__arrow" aria-hidden="true">↓</div>
        <div class="execution-flow__node">Merge response slices</div>
      </section>
    </div>
    <div class="execution-flow__merge">
      <div class="execution-flow__node execution-flow__output">
        Same <code>hero</code> response
      </div>
    </div>
  </div>
  <figcaption>
    Grouping merges selection sets before completion; ungrouped execution merges
    completed response slices afterward.
  </figcaption>
</figure>

In outline, the traversal looks like this:

```text
for selection in selectionSet:
  if directives exclude selection:
    continue

  if selection is an applicable fragment:
    visit its selections using the same output object and scope

  if selection is a field:
    previous = output[responseName]

    if previous is a final null or leaf value:
      continue

    state = scope.fieldStates[responseName]
    completed = execute or continue the field using state and previous
    output[responseName] = merge(previous, completed)
```

This is still field merging. It is *online* field merging: merge when another
occurrence is encountered, rather than collecting every occurrence before any
of them executes.

## Why the resolver-source cache is still cheaper

Ungrouped execution does need a map. When a composite field appears again, the
executor must resume from the object returned by its resolver, not from the
partially completed public response.

After the first `hero` selection, for example, the response contains only:

```json
{
  "hero": {
    "name": "Leia"
  }
}
```

That object cannot resolve `friends`: the original hero object may contain data
that was never exposed in the response. The alternatives are to call the
resolver again, collect all child selections before execution, or retain the
first resolver result. Ungrouped execution retains it.

The TypeScript implementation gives each selection scope a `fieldStates` map.
An entry for an object keeps its raw source, runtime type, and child scope. A
composite list keeps its materialized source items and aligned state for each
item. This is enough to resume an interleaved response position without calling
its resolver, abstract-type resolver, or iterator again.

The important point is what the map does *not* contain. It has entries only for
composite response positions. A completed scalar, enum, leaf list, or final null
is already recorded in the response object and needs no second entry. Nor does
the cache retain arrays of field nodes or construct merged selection sets.

| Allocation | Collected execution | Ungrouped execution |
| --- | --- | --- |
| Private response-name entry | Every distinct response name | Composite response names only |
| Field-node storage | Every occurrence, grouped in arrays | None |
| Leaf completion state | Collected map plus response | Response object only |
| Composite source state | Implicit in grouped completion | Cached until later slices finish |

This explains why the source cache can still be cheaper than a collected-field
map. Its size follows the number of composite positions that might need to
resume, while collection follows every response name and every matching field
node.

Relay-style flattening does not erase that distinction. It removes duplicate
occurrences and child-selection merging, but GraphQL.js still creates a map
entry and a one-node field group for every remaining leaf. Ungrouped execution
writes those leaves directly into the response and reserves `fieldStates` for
composite positions. That is why the flattened benchmark still shows lower time
and observed heap usage.

## What is actually proved

The specification explicitly permits an executor to cancel sibling response
positions that have not finished after a non-null error propagates
([Errors and Non-Null Types](https://spec.graphql.org/September2025/#sec-Errors-and-Non-Null-Types)).
The most direct theorem compares ungrouped execution with a collected executor
that cancels unfinished siblings after a non-null error bubbles through the
active selection set. This is a more like-for-like reference than the
non-canceling specification executor: both executors stop work that can no
longer change the response, and their main structural difference is whether
fields are grouped before execution.

The sibling-canceling executor is itself proved equivalent to the spec-facing
executor at the same response-data-and-error-presence boundary. The direct
theorem therefore requires:

- response data is identical;
- ungrouped execution does not invent an error when sibling-canceling execution
  has none; and
- ungrouped execution does not lose *all* errors when sibling-canceling
  execution has at least one.

The direct theorem is:

```lean
def ungroupedExecutionEquivalentToCancelingSiblingsExecution
    (schema : Schema) (operation : Operation) : Prop :=
  SchemaWellFormedness.schemaWellFormed schema
  -> Validation.operationDefinitionValid schema operation
  -> ∀ {ObjectRef : Type} (resolvers : Resolvers ObjectRef)
        variableValues fuel (source : ResolverValue ObjectRef),
      NormalForm.operationBoolVarsComplete operation
        (GraphQL.Execution.coerceVariableValues operation variableValues)
      -> responseDataAndErrorPresenceEquivalent
          (executeQueryWithFuel schema resolvers variableValues
            operation fuel source)
          (ExecutionCancelingSiblings.executeQueryWithFuel schema resolvers
            variableValues operation fuel source)
```

It quantifies over every resolver environment, variable assignment, fuel value,
and root source in the model. Its boundary is a well-formed schema, a valid
operation, and complete values for Boolean variables used by `@skip` and
`@include` after defaults are applied.

The proof is resolver-parametric. It does not depend on a particular database,
object representation, or resolver implementation. Its structure first proves
an uncached syntax-order executor equivalent to collected sibling-canceling
execution at this response boundary, then proves that adding the
composite-source cache does not change the public result.

Exact error details are excluded because grouping can move work across the
cancellation point, as the next example shows.

The definitions and proof witnesses are in
[`GraphQL/Algorithms/ExecutionUngrouped.lean`](https://github.com/duckki/graphql-lean/blob/main/GraphQL/Algorithms/ExecutionUngrouped.lean)
and
[`Proofs/GraphQL/Algorithms/ExecutionUngrouped`](https://github.com/duckki/graphql-lean/tree/main/Proofs/GraphQL/Algorithms/ExecutionUngrouped).

## Why exact error counts can still differ

Both algorithms use this freedom. The collected executor cancels remaining
response-name groups; ungrouped execution cancels remaining selections in syntax
order.

Field grouping can nevertheless move work across the cancellation point. The
Lean test suite contains this example:

```graphql
{
  hero {
    name
  }
  stop
  hero {
    age
  }
}
```

In this schema, `hero` is nullable, as are its `name` and `age` fields. `stop` is
a non-null root field. The `age` resolver failure therefore records an error and
completes `age` as null, but does not propagate beyond that nullable field or
cancel `stop`.

The resulting execution order is:

| Executor | Work before root cancellation | Errors |
| --- | --- | ---: |
| Ungrouped | `hero.name`, then `stop`; `hero.age` is canceled | 1 |
| Collected, sibling-canceling | grouped `hero.name` and `hero.age`, then `stop` | 2 |

Both responses have `data: null`, and both report that an error occurred. The
difference is acceptable: grouping changed the execution order, but neither the
skipped `hero.age` result nor its error can change the final response data. This
is why the proved relation preserves error presence rather than multiplicity.
Applications that treat every individual error as required telemetry should
evaluate the tradeoff explicitly, because exact error arrays, paths, ordering,
and counts are not preserved.

The executable counterexample is
[`interleavedDuplicateErrorCountsDifferSmoke`](https://github.com/duckki/graphql-lean/blob/main/Tests/GraphQL/Algorithms/ExecutionCancelingSiblings.lean),
and the sibling-canceling executor and its preservation statement are in
[`GraphQL/Algorithms/ExecutionCancelingSiblings.lean`](https://github.com/duckki/graphql-lean/blob/main/GraphQL/Algorithms/ExecutionCancelingSiblings.lean).

## A TypeScript implementation for GraphQL.js

[`graphql-ungrouped-js`](https://github.com/duckki/graphql-ungrouped-js) turns
the algorithm into drop-in GraphQL.js execution entry points. Parsing,
validation, schemas, types, and utilities still come from `graphql`; only the
execution function changes:

```diff
-import { executeSync } from "graphql";
+import { executeSync } from "graphql-ungrouped";
```

`executeSync` is the optimized and benchmarked path. The package also exposes
`execute` for compatibility, but its asynchronous siblings run in syntax order;
async optimization remains future work. Mutations are detected and delegated
to GraphQL.js so their grouped, serial root-field semantics stay unchanged.

The repository contains the implementation, compatibility notes, and full test
suite.

## A synthetic 40,000-field benchmark

Meta's GraphQLConf 2026 talk
[*The 40,000-field Query*](https://graphql.org/conf/2026/schedule/e87d74fcfd6a5bf55d7169e394799f63/)
described large persisted operations with hundreds of fragments and fragment
inlining to reduce `CollectFields` overhead. Meta has also described Relay
compiler flattening as a way to remove duplicate fields before runtime
([*Relay Modern: Simpler, faster, more extensible*](https://engineering.fb.com/2017/04/18/web/relay-modern-simpler-faster-more-extensible/)).

Those reports establish a realistic scale and query shape, but the real
operation is not public. The repository benchmark therefore generates a
synthetic model:

- 40,000 leaf-field occurrences;
- 200 component fragments;
- 1,000 distinct response fields; and
- one concrete story returned through a union.

It compares GraphQL.js and ungrouped synchronous execution on two equivalent
documents. The first retains all overlapping component fragments. The second is
compiler-flattened so each distinct response field appears once. The benchmark
asserts that all four execution results are identical and that resolver-call
counts match.

One run on an Apple M3 with Node 22.23.1 and GraphQL.js 17.0.2 produced:

| Document | GraphQL.js | Ungrouped | Speedup |
| --- | ---: | ---: | ---: |
| Original, unflattened | 2.13 ms | 1.21 ms | 1.76× |
| Preprocessed, flattened | 366.0 μs | 217.7 μs | 1.68× |

The same run's observed heap high-water growth was:

| Document | GraphQL.js | Ungrouped | Reduction |
| --- | ---: | ---: | ---: |
| Original, unflattened | 3.95 MiB | 3.21 MiB | 18.8% |
| Preprocessed, flattened | 1.52 MiB | 1.09 MiB | 28.6% |

The heap figures are median high-water observations from forced
garbage-collection samples, not exact allocation counts. The timings are also one
machine's results for a deliberately selection-heavy synthetic operation. They
are evidence for a mechanism, not a portable performance promise.

The flattened result confirms the mechanism above: avoiding even one-node field
groups still reduces execution overhead.

This benchmark covers synchronous execution only.

## Where this fits

For synchronous queries, ungrouped execution is the better default in this
design. It gives up no sibling concurrency and was faster and leaner on both the
original and Relay-flattened benchmark documents. That is an engineering
recommendation, not a universal timing theorem; representative production
workloads should still be measured.

Async execution needs a different path. The current `execute` implementation
serializes sibling fields, while neither the Lean model nor the benchmark covers
promise scheduling. A future executor could analyze a validated persisted
operation once, use concurrent ungrouped execution when no duplicate composite
response positions remain, and fall back to collected execution otherwise. The
current package does not yet implement or prove that dispatcher.

Mutations remain delegated to GraphQL.js. A future hybrid could preserve
grouped, serial mutation root fields while executing their child selection sets
ungrouped.

The lesson here is that GraphQL execution offers multiple valid choices, and some may
fit your workflow better than the specification's default structure.
Formalization helps uncover those choices and clarify the trade-offs that come
with them.
