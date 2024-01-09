## Inferred Mutability: Safety Proof of Mutability Upgrade

My [previous blog post](https://duckki.github.io/2024/01/01/inferred-mutability.html) proposed the abiilty to upgrade immutable references to mutable ones in Rust or similar languages. The main benefit of this is avoiding unncecessary code duplication implementing both immutable accessor and mutable accessor functions. It amounts to be a mutability generic programming (see a related [Pre-RFC](https://internals.rust-lang.org/t/pre-rfc-unify-references-and-make-them-generic-over-mutability/18846)).

I've discussed this idea at the Rust internal forum and I realized a new syntax is necessary and references of certain types are not eligible for mutability upgrades. In this post, I'll discuss those. Also, I'll sketch the proof of its safety.

### Necessary additions to the language and borrow checker

I propose two new language features. One of them requires a new syntax.

First, in order to establish the stronger "accessibility" relationship between references across function boundaries, we need a new language feature that relates the returned values to arguments.

Example (in Rust):
```rust
struct Example {
    data1: i32,
    data2: i32,
}

fn get_ref( input: & Example, key: i32 ) -> &'input i32 {
    if key == 42 {
        & self.data1
    } else {
        & self.data2
    }
}

fn example1( key: i32 ) {
    let mut v = Example { data1: 1, data2: 2 };
    let r1 = get_ref( &v, key );
    let r2 = &mut r1; // currently now allowed
    *r2 = 3;
}
```

It is safe to upgrade `r1`'s mutability since the reference `r1` is accessible from another mutable variable `v` and there are no other borrows from `v` live at the time of `r2`'s initialization.

However, this is not currently possible in Rust. The usual lifetime constraint in Rust is a "lives-as-long-as" relationship between arguments and returned references. That's not strong enough to prove the returned reference is accessible from the argument.

Thus, we need a new direct accessibility annotation. The `&'input i32` in the return type is a new language feature to indicate the returned referenced is "accessible" from `input` (or a subdata of the argument `input`).

Second, we need to relax lifetime constraints between references that have the same origin of borrow. In the `example1`, there is another reason why `r1` can't be mutably borrowed - another immutable borrow from `v` (the `&v`) is still live. Because `r1` is borrowing from `&v` (via `get_ref`), that keeps `&v` live as long as `r1` is live.

What we need here is to allow both `&v` and `r1` die at the time of `r2`'s declaration. That is safe because both `&v` and `r1` are directly/indirectly borrowing from `v`. We are eliminating the strict lifetime relationship between `&v` and `r1`, by realizing that their relative lifetimes are irrelevant (as long as `v` is live).


### Limitations

#### First limitation: Non-deterministic dependency

```rust
fn longest(x: &str, y: &str) -> &'??? str {
    if x.len() > y.len() {
        x
    } else {
        y
    }
}
```

My current proposal is allowing to specify one argument such as `'x` or `'y` to indicate the returned reference is accessible from `x` or `y`, but my proposal does not allow to specify both.

One can think of a more complex syntax like `fn longest(x: &str, y: &str) -> &'{x, y} str`. But, that can be added later in the future.

#### Second limitation: Structs with immutable fields

Some structs may not be eligible for mutability upgrade. For example,

```rust
struct Ineligible<'a> {
    data: i32,
    immut_ref: &'a i32,
}

fn get_ref_ineligible<'a>(x: &'a Ineligible<'a>, key: i32) -> &'x i32 {
    if key == 42 {
        & x.data
    }
    else {
        x.immut_ref
    }
}

static staticVal: i32 = 0;

fn example2( key: i32 ) {
    let mut v = Ineligible { data: 1, immut_ref: &staticVal };
    let w = get_ref_ineligible( &v, key );
    // not safe to upgrade `w` to a mutable borrow.
}
```

`get_ref_ineligible` might return a reference that can't be mutable, even if its argument was mutable. Thus, it's not safe to upgrade the returned reference to a mutable one.

Structs with an immutable field should fail the eligibility check. For example, a tuple with immutable references.

I don't think this is a loss of functionality, one must write a separate function that guarrantees to return a mutable reference, if necessary. See the following example:

```rust
fn get_ref_ineligible_mut<'a>(x: &'a Ineligible<'a>, key: i32) -> &'x mut i32 {
    & x.data
    // Returning `x.immut_ref` is no longer an option.
}
```

`get_ref_ineligible_mut` can't be implemented the same as `get_ref_ineligible` due to restrictions. They have to be separate implementations. Thus, it won't be a code duplication.

However, the rule can be too restrictive in some cases. What if those immutable references are pointing to the mutable memory within the data structure?

As a future improvelemnt, an additional syntax could be added to indicate that an immutable field must reference another mutable field within the struct. For example,

```rust
struct Eligible2<'a> {
    data: i32,
    immut_ref: &'{mut Self} i32, // can assign `&self.data` here.
}
```

A special annotation like `'{mut Self}` could indicate that `immut_ref` can must reference a mutable subfield of `Eligible2`. Therefore, `immut_ref` can be upgraded to a mutable one, if a mutable `self` reference is live. But, I'm not sure how important this particular use case would be.


### Proof of Safety

Here's the proof of why mutability upgrade is safe under the conditions described above.

Suppose we have a reference `x` to an object of type `T`. Let's define two sets `I(x)` and `M(x)`.

`I(x)`: The set of all accessible immutable references from the immutable version of `x` (`&T`).

`M(x)`: The set of all accessible mutable references from the mutable version of `x` (`&mut T`).

#### Hypothesis

The conditions checked before upgrading an immutable reference `y`:

1) A mutable reference `x` (`&mut T`) is live in the current context, even though it is inaccessible (due to borrowing).

2) `y` is the only live variable borrowing from `x` directly or indirectly.

3) `y` is accessible from `x`. (Thus, `y` is in the set `I(x)`.)

4) `T` has no immutable fields.

#### Proof

5) From (4), `I(x)` is a subset of `M(x)`. (In other words, `I(x) - M(x)` is empty.)

6) From (3) and (5), `y` is in the set `M(x)`.

Conclusion: Since `y` is the only live borrow from `x` from (2) and `y` is in the set `M(x)` from (6), it is safe to upgrade `y` to a mutable reference.


#### Notes

- Smart pointers like `Cell`, `Rc`, etc. are eligible for mutability upgrade and shouldn't cause a safety issue. They prohibit access to their internal references via immutable reference.
- `Box` also doesn't cause a problem, even if it exposes immutable refernce via immutable `self`. Since `Box`'s internal references are not mutably shared, upgrading its immutable internal reference guarantees exclusive access and thus it's safe to mutate.