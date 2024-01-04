## The Properties of Reference

<!-- | | Uniqueness | Exclusivity | Mutability | Mojo | Rust |
| - | ------- | ------- | ------- | ------- | ------- |
| Owner ref | Yes* | Yes* | Yes* | local vars and `owned` args | local vars only |
| Exclusive ref | No | Yes* | Yes* | `inout` args | `&mut` args |
| Shared ref | No | No | No | `borrowed` args | `&` args |

(\* - while not borrowed) -->

A reference can be

- unique
- not unique, but still exclusive
- owner or alias
- mutable or immutable

Let's think about those properties and their relationships.

### Reference Uniqueness

When there is only once reference to a memory, that reference is the unique reference. It implies it is safe to modify the memory. Also, it implies it is safe to deallocate it.

For example, Rust ensures every reference is unique before deallocating it.

### Reference Exclusivity

An exclusive reference is the only accessible reference to the given memory.

Unqiue reference implies exclusivity, but not the other way around.

<!-- - In Rust, exclusive reference can grant an exclusive access to its memory.
    - When an exclusive reference is created, the original reference becomes not accessible until the new reference is no longer live in order to avoid data race.
    - It guarantees that at most one exclusive reference is accessible at a time.
- In Rust, any reference can grant a non-exclusive (shared) access to aliases.
    - When a shared reference is created, the original exclusive reference is not accessible until all shared references are no longer live for safety. -->

### Reference Ownership

Owner reference is unique and exclusive at the beginning.

Owner references are responsible for deallocating the memory, even if there might be non-owner references to the same memory (aliases). So, uniqueness implies ownership, but not the other way around.

In the RAII pattern, declared variables are the owner references. But, (unsafe) pointers have no owners designated.

In Rust, there is no way to pass owned references to other functions. The viable alternative is moving objects around. In this sense, ownership is restricted to the declared function in Rust.

### Reference Mutability

Mutability implies exclusivity in Rust, but not the other way around.

For example, a local variable can be declared immutable, while it will start out to be a unique, exclusive and owner reference. So, exclusivity doesn't always mean mutability.

Also, there is a situation where immutable reference turns out to be the only accessible reference (thus, the exclusive reference). That happens when it's the only live borrow from a mutable reference. By the way, in this case, I argue that it should be [allowed to upgrade to a mutable reference](https://duckki.github.io/2024/01/01/inferred-mutability.html).

### Summary of the Relationships

- Uniqueness implies ownership.
- Ownership implies uniqueness and exclusivity, unless borrowed.
- Mutability implies exclusivity.
- Exclusivity implies mutability, unless prohibited.

<!-- ### Borrow Rules

- Getting borrowed gives up the uniqueness/exclusivity/mutability, if any.
- Borrowing can be either exclusive or non-exclusive.
- Non-exclusive references can be borrowed non-exclusively again. -->

### Conclusion

- Uniqueness is a state of owner reference and it doesn't seem to be useful to declare an owner reference to be unique permanantly.
- Ownership should be allowed to be passed around for flexibility. Thus, owner and mutable reference types need to be distinguished in programming languages.
- While mutability and exclusivity are not exactly the same, it's unclear whether it's worth having separate mutable and exclusive reference types in programming languages. Mutable reference type alone may be enough.
- Immutable references can be exclusive, but they are not allowed to be converted/upgraded to mutable references, even if it's safe to do so.