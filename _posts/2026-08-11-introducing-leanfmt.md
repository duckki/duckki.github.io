---
title: "Introducing LeanFmt: A Code Formatter Written in Lean"
date: 2026-08-11 18:52:58 -0700
description: "LeanFmt formats Lean code with syntax-aware layout, leading operators, code-preservation checks, and support for project-specific syntax."
tags:
  - Lean
  - Developer tools
  - Code formatting
  - Open source
---

<!-- cspell:words LeanFmt leanfmt mathlib pretty-lean idempotency codebase subselections -->

Today I am introducing [LeanFmt](https://github.com/duckki/leanfmt), an
opinionated code formatter for Lean, written in Lean itself.

Here is the style at a glance.

Before:

```lean
def parenthesizedConjunctionChain (schema : Schema) : Prop :=
  namesAreUnique (schema.allTypes.map TypeDefinition.name) ∧
    schema.objectType schema.queryType ∧
    (∀ typeDefinition, typeDefinition ∈ schema.types
      -> typeDefinitionWellFormed schema typeDefinition) ∧ (∀ typeName objectTypeName,
          objectTypeName ∈ schema.getPossibleTypes typeName
    -> schema.objectType objectTypeName)
```

After:

```lean
def parenthesizedConjunctionChain (schema : Schema) : Prop :=
  namesAreUnique (schema.allTypes.map TypeDefinition.name)
  ∧ schema.objectType schema.queryType
  ∧ (∀ typeDefinition,
      typeDefinition ∈ schema.types -> typeDefinitionWellFormed schema typeDefinition)
  ∧ (∀ typeName objectTypeName,
      objectTypeName ∈ schema.getPossibleTypes typeName
      -> schema.objectType objectTypeName)
```

The first token of each continuation line tells you how it connects to the
previous line. Indentation exposes the structure inside each operand. This is
the central idea behind LeanFmt's style.

LeanFmt parses complete files with Lean's own parser, preserves source tokens
and comments, and changes whitespace around them. It understands ordinary Lean
declarations and expressions, loads syntax extensions from the target project,
and falls back conservatively when it encounters syntax without a dedicated
formatting rule.

## Why another Lean formatter?

Lean FRO has a code formatter on its roadmap, but I needed one now. I work with
large amounts of Lean code, including code produced with AI assistance, and I
wanted one command to keep it in a consistent style.

I also wanted formatting to make Lean's structure easier to scan. Many formatters
place a binary operator at the end of the previous line. LeanFmt generally places
it at the beginning of the continuation instead. The operator then works like a
visual connector, while indentation remains available to show nesting.

LeanFmt has one formatting option at the moment, which is the line width:
90 characters by default, or a project-specific value such as Mathlib's 100.

## The style, mostly by example

### Operators lead continuation lines

```lean
def result : Prop :=
  firstCondition
  ∧ secondCondition
  ∧ finalCondition
```

Mixed operators at the same precedence remain peers:

```lean
def result :=
  firstValue
  + secondValue
  - thirdValue
```

Nested logical groups keep a visible hierarchy:

```lean
def validImplementation : Prop :=
  (schema.isLeafType implementation
    ∧ schema.isLeafType expected
    ∧ implementation = expected)
  ∨ (schema.isCompositeType implementation
      ∧ schema.isCompositeType expected
      ∧ ∀ objectName,
          schema.typeIncludesObject implementation objectName
          -> schema.typeIncludesObject expected objectName)
```

The outer `∨` is visible immediately. The nested `∧` chain is one level deeper.

### Declaration headers flow at structural boundaries

```lean
def lookupVariableValue? (variableValues : VariableValues) (name : Name)
    : Option InputValue :=
  body
```

```lean
def mergeSelectionSets (schema : Schema) (parentType : Name)
    (leftSelectionSet : List Selection) (rightSelectionSet : List Selection)
    : List Selection :=
  leftSelectionSet ++ rightSelectionSet
```

The declaration name stays with `def`. Parameters wrap at binder boundaries.
A long result type begins with `:` at the declaration-continuation indentation.

Separators stay with their headers:

```lean
def result :=
  longDefinitionBody

let value :=
  longComputation

let value ←
  longAction

| pattern =>
    longArmBody
```

LeanFmt does not leave `:=`, `←`, `=>`, or an introducing `let` stranded on a
line by itself.

### Applications wrap without incidental alignment

```lean
singleFieldResult responseName
  (completeValue schema resolvers variableValues
    fuel' fieldDefinition.outputType
    (field :: fields) resolved)
```

Continuation indentation follows the nested application structure. It does not
align every line under an arbitrary token from the first line.

### Quantifiers expose their bodies

```lean
def mixedAdjacentQuantifiers : Prop :=
  ∃ objectType,
    ∀ typeCondition,
      typeCondition ∈ typeConditions
      -> objectType ∈ schema.getPossibleTypes typeCondition
```

```lean
fun objectType =>
  normalizeSelectionSet schema objectType selections
```

Quantifier bodies break after the comma. Lambda bodies break after `=>`.

### `let`, `if`, and `match` preserve offside structure

```lean
def withLet : Result :=
  let normalizedSubselections :=
    normalizeSelectionSet schema returnType mergedSubselections
  normalizedSubselections
```

```lean
if firstCondition then
  firstResult
else if secondCondition then
  secondResult
else
  finalResult
```

```lean
match variableValues with
| [] => none
| (variableName, value) :: rest =>
    if variableName = name then some value else lookupVariableValue? rest name
```

The successful continuation of a `let` returns to the `let` column. Conditional
branches break as one balanced structure. Match alternatives align with
`match`, and a long arm body starts below `=>`.

### Collections break as balanced units

```lean
[
  veryLongFirstArrayItemName,
  veryLongSecondArrayItemName,
  veryLongThirdArrayItemName
]
```

```lean
{
  operation with
    selectionSet :=
      normalizeSelectionSet schema operation.rootType operation.selectionSet
}
```

When a multi-item collection does not fit, its opening boundary, item
boundaries, and closing delimiter break together. LeanFmt does not add a
trailing comma that was not present in the source.

### Proofs and comments stay yours

```lean
theorem theoremArrowChain (h : HypothesisWithEnoughCharactersForLayoutTesting)
    : FirstCondition -> SecondCondition -> FinalCondition := by
  exact proof
```

LeanFmt formats the theorem header but preserves the source layout of the proof.
It also preserves line comments, nested block comments, doc comments, and their
text. Comments move with the surrounding structure when indentation changes,
but their contents are not wrapped or rewritten.

For intentionally hand-laid-out code, formatting can be disabled for the next
syntax node:

```lean
-- leanfmt: off next
def handAligned   :   Nat:=
       1
```

Or for a region:

```lean
-- leanfmt: off
def handAligned   :   Nat:=
       1
-- leanfmt: on
```

## Structure preservation is the contract

Formatting Lean is more than printing an abstract syntax tree. Real projects
contain comments, parser extensions, generated notation, layout-sensitive
constructs, and proof scripts whose authored structure matters.

LeanFmt is built around four checks:

1. Parse the file with Lean and the project's active syntax extensions.
2. Reconstruct the parsed source from a lossless syntax tree.
3. Preserve code tokens, token order, and the exact text inside comments.
4. Reach a fixed point: formatting the output again must produce the same text.

The formatter is conservative when it cannot satisfy that contract. Formatting
can take more than one parse-and-render pass to converge. If a result stops
parsing, cycles, or does not converge within four passes, LeanFmt reports the
problem and returns the original source.

Unknown syntax is still kept losslessly. A generic structural rule can wrap it
at parser-child boundaries without pretending to understand what the extension
means. Project-specific imports are loaded so the formatter sees the same parser
environment as the code it is formatting.

## A formatter is a small typesetting system

The implementation resembles a constrained typesetting pipeline:

```text
Lean parser
  -> lossless syntax tree
  -> syntax regrouping
  -> spacing and line-break rules
  -> resolved layout plan
  -> width-aware renderer
```

The syntax tree retains every token and comment. Regrouping turns selected raw
parser shapes into logical applications, infix chains, collections, and other
structures that formatting rules can reason about. Spacing and line breaking
are separate decisions. The renderer performs fit checks, chooses a layout under
the width budget, computes indentation, and emits text.

The separation is deliberate: syntax rules decide *where* a break is allowed;
the renderer decides *whether* the candidate layout fits. The renderer does not
recognize Lean syntax by token spelling, and syntax rules do not inspect the
current output column.

This is typesetting for a language with a stricter contract. Visual quality
matters, but parse structure, source tokens, comments, and idempotency are not
negotiable.

## Validation at Mathlib scale

I have been using LeanFmt on my own Lean projects for several weeks. I also
validated version 0.3.0 against the complete `Mathlib` directory from Mathlib
4.32.0: 8,264 tracked Lean files, formatted at a 100-character width.

All files passed the code-preservation, missing-rule, fallback,
line-overflow, and idempotency checks. The complete post-format Mathlib build
also passed. I reviewed representative output throughout the process and used
independent AI reviews to scan the broad formatting delta for suspicious layout.

That does not mean every layout is perfect. A few minor formatting imperfections
remain, especially around difficult source-preserved regions, and LeanFmt is
still under active development. But the result is already useful enough that I
use it on real projects.

## Try it

Add the current release to your Lake package:

```toml
[[require]]
name = "leanfmt"
git = "https://github.com/duckki/leanfmt.git"
rev = "v0.3.0"
```

Keep your project's Lean toolchain when resolving the dependency:

```sh
lake update --keep-toolchain
```

Then format a file or directory:

```sh
lake exe fmt MyProject/File.lean
lake exe fmt --recursive MyProject
lake exe fmt --line-width 100 --recursive MyProject
```

Check formatting in CI without changing files:

```sh
lake exe fmt --check --recursive MyProject
```

LeanFmt uses parallel workers for multi-file package runs. It follows the
project's pinned Lean toolchain and currently tests the v4.29, v4.30, v4.31, and
v4.32 release lines in CI. The released package depends only on Lean and is
available under the MIT license.

## Help shape LeanFmt

LeanFmt expresses one opinionated style, not the only possible Lean style. I
would love to hear which layouts work for you, which do not, and which options
would make it useful for your project.

I would also be happy to compare notes with the team working on Lean's official
formatter. Even if LeanFmt ultimately informs rather than becomes the standard
tool, building and validating it has exposed useful lessons about lossless
syntax, layout-sensitive parsing, comments, custom notation, and formatter
correctness.

The source, issue tracker, complete formatting guide, and implementation notes
are all in the [LeanFmt repository](https://github.com/duckki/leanfmt).
