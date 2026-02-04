# Chapter 2: Lambda Calculus

## Overview

In 1936, the same year Turing published his paper on computable numbers, Alonzo Church published a radically different model of computation. Where Turing imagined a machine with a tape and a head, Church imagined nothing but **functions**.

Lambda calculus has no:
- Memory
- Variables (in the traditional sense)
- Numbers (built-in)
- Data structures
- Loops or conditionals

Yet it can compute anything a Turing machine can. This chapter explores how.

## The Syntax

Lambda calculus has only three things:

```
1. Variables:        x, y, z, ...
2. Abstraction:      λx.M     (a function with parameter x and body M)
3. Application:      M N      (apply function M to argument N)
```

That's it. Everything else is built from these primitives.

## Functions All the Way Down

### Identity

The simplest function—returns its argument:

```
I = λx.x

I 5 = 5
I (λy.y) = λy.y
```

### Self-Application

A function that applies its argument to itself:

```
ω = λx.x x

ω I = I I = I
ω ω = (λx.x x)(λx.x x) = (λx.x x)(λx.x x) = ... (infinite loop!)
```

### Currying

Functions of multiple arguments are expressed as nested single-argument functions:

```
ADD = λx.λy.x + y    (assuming we had +)

ADD 3 = λy.3 + y     (partial application)
ADD 3 5 = 8
```

## Church Encodings

With only functions, how do we represent data?

### Booleans

```
TRUE  = λx.λy.x    (returns first argument)
FALSE = λx.λy.y    (returns second argument)

IF = λp.λa.λb.p a b

IF TRUE  "yes" "no" = TRUE "yes" "no" = "yes"
IF FALSE "yes" "no" = FALSE "yes" "no" = "no"
```

Booleans *are* if-statements!

### Numbers (Church Numerals)

Numbers are "how many times to apply a function":

```
0 = λf.λx.x           (apply f zero times)
1 = λf.λx.f x         (apply f once)
2 = λf.λx.f (f x)     (apply f twice)
3 = λf.λx.f (f (f x)) (apply f three times)
```

### Arithmetic

```
SUCC = λn.λf.λx.f (n f x)    (add one more application)

SUCC 2 = λf.λx.f (2 f x)
       = λf.λx.f (f (f x))
       = 3

ADD = λm.λn.λf.λx.m f (n f x)   (apply f m times, then n times)
MUL = λm.λn.λf.m (n f)          (apply "n applications" m times)
```

### Pairs and Lists

```
PAIR = λx.λy.λf.f x y
FST  = λp.p TRUE
SND  = λp.p FALSE

PAIR 1 2 = λf.f 1 2
FST (PAIR 1 2) = (λf.f 1 2) TRUE = TRUE 1 2 = 1
```

## Recursion Without Names

The Y combinator enables recursion without named functions:

```
Y = λf.(λx.f (x x))(λx.f (x x))

Y g = g (Y g) = g (g (Y g)) = g (g (g (Y g))) = ...
```

Factorial without naming itself:

```
FACT = Y (λf.λn.IF (ISZERO n) 1 (MUL n (f (PRED n))))
```

## The Church-Turing Thesis

Lambda calculus and Turing machines compute exactly the same things. This suggests that "computability" is a fundamental concept, independent of the model we use to define it.

```
┌─────────────────────────────────────────────────────────────┐
│                    EQUIVALENT MODELS                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Turing Machine ←──────────────→ Lambda Calculus            │
│         ↑                              ↑                     │
│         │                              │                     │
│         ↓                              ↓                     │
│   Register Machine ←────────────→ Recursive Functions        │
│         ↑                              ↑                     │
│         │                              │                     │
│         ↓                              ↓                     │
│   Cellular Automata ←───────────→ Combinatory Logic          │
│                                                              │
│   All compute the same class of functions!                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Lambda in Hardware

Here's the remarkable connection to hardware:

| Lambda Concept | Hardware Equivalent |
|---------------|---------------------|
| TRUE/FALSE | Mux select line |
| IF-THEN-ELSE | Multiplexer |
| PAIR | Register pair |
| Church numeral | Counter |
| Y combinator | Feedback loop |

A multiplexer *is* Church's IF:

```
MUX(sel, a, b) = sel ? a : b

IF = λsel.λa.λb.sel a b

They're the same function!
```

## Why Lambda Calculus Matters

1. **Foundation of functional programming** - Lisp, Haskell, ML all descend from lambda calculus
2. **Type theory** - Types are propositions, programs are proofs
3. **Compiler theory** - Lambda is the intermediate representation of choice
4. **Understanding computation** - Strips computation to its essence

## Hands-On Exercises

### Exercise 1: Evaluate
Evaluate step by step: `(λx.λy.x y)(λz.z) a`

### Exercise 2: Define NOT
Using only TRUE and FALSE, define NOT.

### Exercise 3: Predecessor
PRED is surprisingly tricky. Research and implement it.

## Key Takeaways

1. **Functions are enough** - No built-in data types needed
2. **Data is behavior** - Booleans select, numbers iterate
3. **Recursion without names** - Y combinator is magic
4. **Equivalent to Turing machines** - Same computational power
5. **Hardware implements lambda** - Muxes are Church booleans

> See [Appendix B](appendix-b-lambda-calculus.md) for Church encodings implemented in RHDL.
