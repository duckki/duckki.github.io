---
title: "Formalization-First Development: What Should Humans Review?"
date: 2026-09-13 00:00:00 -0700
description: "An experiment in turning a paper algorithm into a Lean specification, a proved floating-point implementation, and tested Python and Rust ports."
tags:
  - Software engineering
  - Lean
  - Formal methods
  - AI
  - Numerical computing
---

<!-- cspell:words ARTEMIS bigl bigr binary64 Bury CAPSTONE Chebyshev ephemeris f64 Finset GNC GSFC heliophysics infty LRO mathbb mathrm noncomputable operatorname roundoff Sośnica UInt Zajdel -->

A friend who works in
[orbit determination and guidance, navigation, and control](https://www.nasa.gov/reference/jsc-guidance-navigation-control-subsystems/)
(OD/GNC) asked Claude whether formal methods would be useful in his field. The
answer was skeptical—or at least reserved.

That was fair. OD/GNC software sits on top of physical models, noisy sensors,
numerical solvers, estimation algorithms, and operational assumptions. Proving
a tidy algebraic property about one small function does not prove that a
spacecraft will go where we want it to go.

So I set myself a more concrete challenge: **Can an AI agent take an algorithm
from an OD/GNC paper, implement it, and prove a meaningful correctness property
about the complete software function?**

I more or less randomly chose Bury, Zajdel, and Sośnica's paper,
["Design of the broadcast ephemerides for the Lunar Communication and
Navigation Services system"](https://doi.org/10.1186/s40645-024-00676-1), and
formalized its Chebyshev position-reconstruction algorithm. The particular
paper was not the point; it provided a realistic test case.

I used [Lean](https://lean-lang.org/), a programming language and proof
assistant, to formalize the paper's algorithm and verify its floating-point
implementation. For every supported decoded message and query time, the Lean
receiver is proved to succeed, return finite coordinates, and stay within 10
micrometers per axis of the ideal real-number algorithm. I also produced
ordinary Python and Rust implementations and tested them against the Lean
versions. The complete
[Chebyshev ephemeris project](https://github.com/duckki/chebyshev-ephemeris) is
available on GitHub.

![The Moon against a star field with turquoise orbital paths labeled LRO, ARTEMIS P1, and ARTEMIS P2.](/assets/images/formalization-first-lunar-satellite-orbits.jpg)

*NASA's heliophysics fleet in orbit around the Moon. Source:
[NASA Scientific Visualization Studio](https://svs.gsfc.nasa.gov/5609).*

## From spec-driven to formalization-first

[GitHub's Spec Kit](https://github.com/github/spec-kit/blob/d848fb4e18f44640ad6b42e60a280551ee90cdce/spec-driven.md)
describes spec-driven development as making the specification the primary
artifact and letting the implementation follow from it. That direction makes
particular sense for AI: settle what we mean, then ask the agent to build it.

This project follows that idea in a particularly literal way: paper to Lean
specification, Lean specification to proved Lean implementation, and Lean
implementation to Python and Rust. *Formalization-first development* makes the
specification formal and machine-checkable before producing the familiar
implementation artifacts. It adds two things to the package:

- a **formal specification** that gives the intended behavior a precise,
  machine-readable meaning;
- a **formal proof** that the implementation satisfies that specification.

A prose specification is still helpful, especially for goals, context, and
decisions that are not mathematical. Tests remain valuable too. What changes is
that a formal specification and proof become part of the deliverable.

The human and AI roles differ at each step. Here, *AI-assisted* means that a
person actively shapes the artifact with the agent; *AI-driven* means that the
agent carries out the work from reviewed inputs and constraints.

- Writing the Lean specification is AI-assisted. Human interaction matters
  because this is where the intent is interpreted and ambiguities become
  concrete choices.
- Writing the Lean proof is AI-driven once the specification and intended
  guarantee are settled.
- Writing the Lean implementation can be AI-assisted or AI-driven, depending on
  how much design direction the human wants to provide.
- Porting the reviewed Lean implementation to other languages is AI-driven.

![A flow diagram shows a paper becoming a Lean specification, a correctness statement, and a machine-checked proof, followed by a proved Lean reference and peer production implementations in Python, Rust, JavaScript, or other languages.](/assets/images/formalization-first-assurance-package.svg)

The formal artifacts do not replace the production code. The specification and
proof travel with it as an assurance package.

## The paper's math remains recognizable in Lean

An ephemeris message carries coefficients that let a receiver calculate a
satellite's position at a requested time. The algorithm normalizes the time,
builds 11 Chebyshev basis values, and sums one polynomial for each of the X, Y,
and Z coordinates.

Here is the core mathematics. Let `t₀` and `t₁` bound the message's validity
interval, `a` be its transmitted coefficients, and `k` select an axis:

$$
\begin{aligned}
x(t) &= 2\frac{t-t_0}{t_1-t_0}-1, \\
T_0(x) &= 1,
& T_1(x) &= x, \\
T_{i+2}(x) &= 2xT_{i+1}(x)-T_i(x), \\
p_k(t) &= \sum_{i=0}^{10} a_{k,i}T_i(x(t)),
& k &\in \{X,Y,Z\}.
\end{aligned}
$$

Here is the corresponding real-number specification in Lean:

```lean
def normalizeEpoch (jdMin jdMax t : ℝ) : ℝ :=
  2 * ((t - jdMin) / (jdMax - jdMin)) - 1

def chebyshevT (x : ℝ) : Nat → ℝ
  | 0 => 1
  | 1 => x
  | n + 2 => 2 * x * chebyshevT x (n + 1) - chebyshevT x n

noncomputable def polynomialCoordinate
    (n : Nat) (a : List ℝ) (x : ℝ) : ℝ :=
  ∑ i ∈ Finset.range (n + 1),
    a.getD i 0 * chebyshevT x i
```

The normalization, base cases, recurrence, and coordinate sum each have a clear
counterpart. A domain expert can compare the paper and specification one item
at a time, before considering floating-point code or control flow.

## Prove the whole receiver, not a toy property

After reviewing what the algorithm means, the next question is what the actual
floating-point function promises. The property to prove is:

$$
\begin{aligned}
\forall m,t,\quad
&\operatorname{ValidMessage}(m) \land \operatorname{InWindow}(m,t) \\
&\Longrightarrow \exists r,\quad
  \operatorname{evaluate}_{64}(m,t)=\operatorname{ok}(r) \\
&\qquad\land\ \operatorname{finite}(r)
  \land \lVert r-\operatorname{reconstruct}_{\mathbb R}(m,t)\rVert_\infty
  \le 10^{-5}\ \mathrm{m}.
\end{aligned}
$$

Here, `ValidMessage` means that the message has the supported field ranges and
coefficient layout, while `InWindow` means that the query falls within its
validity period.

The Lean theorem has the same structure:

```lean
theorem uniformAccuracy (m : Message) (time : UInt64)
    (hm : ValidMessage m)
    (ht : InWindow m time) :
  ∃ result,
    evaluate m time = .ok result ∧
    Binary64Within result (reconstruct m time) (1 / 100000)
```

[**`evaluate`**](https://github.com/duckki/chebyshev-ephemeris/blob/195eb406de11ad1102ce6df0b746ef84c2a0cbba/Ephemeris/Implementation/Float/PositionReconstruction.lean#L41)
is the floating-point implementation of the receiver, and
[**`reconstruct`**](https://github.com/duckki/chebyshev-ephemeris/blob/195eb406de11ad1102ce6df0b746ef84c2a0cbba/Ephemeris/Definitions/PositionReconstruction.lean#L116)
is the real-number specification.
The helper `Binary64Within` includes finite coordinates and the per-axis error
bound. Together, these statements specify the complete evaluator: accepted
input, successful return, finite output, and a uniform accuracy bound against
the real-number specification. This is a guarantee about the complete
function, not just one example or an intermediate algebraic property.

It verifies position reconstruction from a decoded message, not the entire
orbit-determination pipeline. That is the point: prove one whole software
function and state exactly what the proof covers.

## The production code stays the same

The core Python loop is unsurprising:

```python
argument = normalized_epoch(message, time)
basis = [1.0, argument]

for i in range(2, 11):
    basis.append(2.0 * argument * basis[i - 1] - basis[i - 2])

position = []
for axis in message.coefficients:
    total = 0.0
    for i in range(11):
        total += coefficient(axis[i]) * basis[i]
    position.append(total)
```

You review this code as usual: operation order, validation, types, error
handling, integration, and maintainability. But you no longer have to establish
the algorithm's numerical correctness from code review alone.

The project has a mathematical real specification, a floating-point model,
native Lean code, and Python and Rust ports. The proof connects the
floating-point model to its native Lean execution. An AI agent checked the ports
using differential fuzz testing, an established technique that runs generated
inputs through multiple implementations and compares the results. A recorded
campaign ran 30,464 requests across all four evaluators. Of those, 20,177
produced positions; the rest exercised rejection behavior. For successful
queries, all native implementations agreed bit for bit.

This provides practical assurance that the ports preserve the verified Lean
behavior. As tooling and techniques improve, this step may eventually be
strengthened with a full, machine-checked proof of mathematical equivalence
across languages.

## A plausible mistake, caught by the proof

The paper's formula subtracts two times. An implementer might reasonably convert
both absolute microsecond timestamps to floating point and then subtract:

```python
# Plausible, but wrong for large absolute timestamps.
elapsed = float(query_us) - float(start_us)

# Preserve the exact small difference before conversion.
elapsed = float(query_us - start_us)
```

These expressions are equal over the real numbers. They are not equivalent in
binary64. At about `2.126e17` microseconds, adjacent representable values are 32
microseconds apart, so a one-microsecond query offset can disappear.

For one constructed valid message, the plausible mistake produces about 0.56
millimeters of position error: 55.6 times the theorem's 10-micrometer limit.
It demonstrates the kind of ordinary implementation mistake that the
whole-function theorem rules out.

## What changes for the reviewer

Formalization-first development does not remove human review. It lightens the
burden by separating it into smaller questions:

| Artifact | Human review | Evidence in the package |
| --- | --- | --- |
| Formal specification | Does this faithfully capture the intent? | Lean makes every definition precise and type-checkable. |
| Whole-function theorem | Is this the guarantee we actually need, over the right inputs? | Lean checks that the proved implementation satisfies it for every supported input. |
| Lean, Python, and Rust code | Is the code maintainable and suitable for production? | Proof covers Lean; differential tests compare the ports against it. |

The reviewer still brings domain expertise and software judgment, but no longer
has to reconstruct the algorithm's correctness from implementation code alone.
Once the formal specification and promised error bound are accepted, Lean
handles the exhaustive floating-point reasoning for the Lean implementation.
Code review can focus on maintainability, integration, and language-specific
risks. Differential fuzz testing provides additional evidence that the
production ports preserve the proved behavior.

## What it cost

Producing the Lean, Python, and Rust implementation package took roughly half a
day of AI-agent work before human review. It was not half a day of focused human
engineering. The agent did most of the translating, implementing, proving,
porting, testing, and refactoring while I periodically steered it and answered
questions.

I spent additional time searching for a suitable example and learning an
unfamiliar paper and codebase. A domain expert with a clear target would not
need that exploration. With reusable AI skills, much of the remaining
interaction can also be automated. Compared with asking an agent for code alone,
the LLM may need a few additional hours to produce the formal specification and
proofs. Human review remains a separate cost, but it begins with a much better
package.

## Code, or code with evidence?

For this project, formalization-first development produced:

- a recognizable real-number specification tied to the paper's algorithm;
- a Lean floating-point implementation with a **whole-function guarantee**:
  success, finite output, and at most 10 micrometers of per-axis arithmetic
  error for every supported message and query;
- ordinary Python and Rust implementations, differentially tested against the
  proved Lean executions.

The formal specification makes the intended algorithm easier to review. The
theorem turns “correct” into a concrete promise. The proof checks that promise
over the entire supported input space, including numerical cases that ordinary
examples may miss. That moves exhaustive correctness reasoning out of
line-by-line code review. Together, these artifacts form a durable assurance
package that can be rechecked whenever the implementation changes.

AI can already give us plausible code from prose. If the agent can also spend a
few more hours assembling evidence, which deliverable would you rather receive:
**the code alone, or the code together with its formal specification and a
machine-checked proof that the whole function meets its stated guarantee?**
