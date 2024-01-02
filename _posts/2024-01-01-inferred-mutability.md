## Inferred Mutability: A Cure for Rust's Mutability Madness

In Rust, when a function returns a reference, it has to be either immutable or mutable. Thus, structs proving an accessor method are expected to implement both [`Index`](https://doc.rust-lang.org/std/ops/trait.Index.html) and [`IndexMut`](https://doc.rust-lang.org/std/ops/trait.IndexMut.html) traits. Moreover, their implementations can't share the code, leading to [code duplication](https://stackoverflow.com/questions/37914373/how-to-avoid-redundant-code-when-implementing-index-and-indexmut-in-rust).

### Examples

```rust
struct Example {
    // This example struct is simple, but imagine a complex data structure.
    data1: i32,
    data2: i32,
}

impl Example {
    pub fn get_some_ref_mutable( &mut self, key: i32 ) -> & mut i32 {
        // This code is simple, but imagine a complex algorithm retreiving a reference.
        if key == 42 {
            &mut self.data1
        } else {
            &mut self.data2
        }
    }
}
```

The function `get_some_ref_mutable` does NOT mutate `self`, but `self` has to be declared as `&mut`. It just needs to return a mutable subdata reference.

Now, suppose we want the same functionality, but want to work with immutable references. One has to implement a clone of the same function like below:

```rust
    // immutable version
    pub fn get_some_ref( &self, key: i32 ) -> &i32 {
        if key == 42 {
            & self.data1
        } else {
            & self.data2
        }
    }
```

Moreover, the implementations can't share the other function's code, even if they are practically the same code:
```rust
    pub fn get_some_ref( &self, key: i32 ) -> &i32 {
        // You can't re-use `get_some_ref_mutable`.
        return self.get_some_ref_mutable( key ); // error: `self` is not mutable.
    }
```

The fundamental issue in Rust is that the mutability of returned reference is not really a concern of the function returning it. We better let the caller to resolve the mutability of returned value based on the context.


### Solution: Inferred Mutability

Here's simpler example with a reasoning behind this idea.

```rust
fn not_working() {
    let mut v = Example { data1: 1, data2: 2 };
    let x1 = &v;
    let x2 = &x1.data1;
    *x2 = 4; // currently, not allowed
}
```

We can work around it by executing an identical mutable access:
```rust
fn workaround() {
    let mut v = Example { data1: 1, data2: 2 };
    let x1 = &v;
    let x2 = &x1.data1;
    // *x2 = 4; // currently, not allowed
    let x3 = &mut v.data1; // Note: x2 and x3 are the same reference.
    *x3 = 4; // ok
}
```
That works. But, that's silly since we are recalculating the same reference for no good reasons.

Logically, I think we need two new lifetime/mutability rules.

#### Rule 1: Upgrading to Mutable Borrow

When an immutable borrow is the only borrow of a mutable value, the borrow checker shall allow upgrading it to a mutable borrow.

Example:
```rust
fn rule1() {
    let mut v = Example { data1: 1, data2: 2 };
    let w1 = &v.data1; // immutable borrow
    // two possibilities
    if ... {
        // 1) implicit upgrade
        // `w1` is no longer live.
        *w1 = 4; // currently, not allowed
    }
    else {
        // 2) explicit upgrade via a new variable declaration
        let w2 = &mut w1; // currently, now allowed.
        // `w1` is no longer live.
        *w2 = 4;
    }
}
```

Among those two possibilities, considering the benefit of `let mut` / `&mut` declarations, I think the explicit upgrade is more desirable.

#### Rule 2: Flattening Nested Borrows

The Rule 1 alone won't resolve the issue in the `not_working` example. That's because `x2` is not the only borrow of `v`.

```rust
fn rule2() {
    let mut v = Example { data1: 1, data2: 2 };
    let x1 = &v;
    let x2 = &x1.data1;
    // `x1` is no longer live.
    let x3 = &mut x2; // currently, not allowed
    // `x2` is no longer live.
    *x3 = 4;
}
```

The problem is that, because`x2` is borrowing from `x1.data1`, that keeps `x1` live. What we need is to allow both `x1` and `x2` die at the time of `x3`'s declaration.

The borrow structure before `let x3 = ...` is `v --> x1` and `x1.data1 --> x2`. At that time, the rule 2 allows `x1.data1 --> x2` to be flattened as `v.data1 --> x2` by replacing (or instantiating) `x1` with `v.data1`. This restructuing eliminates the lifetime constraint between `x1` and `x2`, allowing `x1` to die before `x2`, which inverts their usual lifetime schedules. The intuition is that `x1` and `x2` are both borrowing from `v`. As long as `v` is live, both of them are safe.

The lifetime inversion allows `x2` to be the only borrow at the time of `x3` declaration, thus allowing mutability upgrade (the rule 1).

Borrow flattening only makes sense between immutable borrows, thus this rule won't apply to mutable borrows.

### Conclusion

I propose to take mutability as something proved by compiler, instead of something prescribed syntactically. It effectively provides a way to implement accessor methods and search functions in a mutability-generic fashion.


### Side Notes

This post is derived from [the Mojo community discussion](https://github.com/modularml/mojo/discussions/1568) that I started.

Mutability annotations like `let mut` and `&mut` have value. They clarify the intention of programmer. So, I'm not suggesting to eliminate that (aka "mutpocalypse").

Also, what I'm suggesting is actually inferred exclusivity (or uniqueness). (See [Niko's blog post](https://smallcultfollowing.com/babysteps/blog/2014/05/13/focusing-on-ownership/) on this) But, to avoid any more confusion, let's just call it "inferred mutability" for now.
