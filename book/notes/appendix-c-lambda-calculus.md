# Appendix C: Lambda Calculus

Lambda calculus is an alternative model of computation developed by Alonzo Church in the 1930s—the same decade Turing invented his machine. While Turing machines manipulate symbols on a tape, lambda calculus manipulates functions. Both are equivalent in computational power, but lambda calculus feels more familiar to programmers.

## The Core Idea

Lambda calculus has just three things:

1. **Variables**: `x`, `y`, `z`, ...
2. **Function abstraction**: `λx.body` (a function with parameter `x`)
3. **Function application**: `f x` (apply function `f` to argument `x`)

That's it. No numbers, no loops, no if-statements. Yet this is enough to compute anything.

## Syntax

```
Expression ::= Variable           -- x, y, z
            |  λVariable.Expression   -- function definition
            |  Expression Expression  -- function application
```

### Examples

```
λx.x                -- Identity function (returns its argument)
λx.λy.x             -- Function that returns its first argument
λf.λx.f (f x)       -- Apply f twice to x
```

### Parentheses Convention

- Application is left-associative: `f g x` means `(f g) x`
- Lambda extends as far right as possible: `λx.x y` means `λx.(x y)`

## Computation: Beta Reduction

The only computation rule is **beta reduction**: applying a function substitutes the argument for the parameter.

```
(λx.body) arg  →  body[x := arg]
```

Read: "Apply lambda-x-dot-body to arg, get body with x replaced by arg"

### Example 1: Identity Function

```
(λx.x) 5
→ 5        -- substitute 5 for x in "x"
```

### Example 2: Constant Function

```
(λx.λy.x) a b
→ (λy.a) b     -- substitute a for x, get λy.a
→ a            -- substitute b for y in "a" (y doesn't appear, so no change)
```

### Example 3: Self-Application

```
(λx.x x)(λy.y)
→ (λy.y)(λy.y)    -- substitute (λy.y) for x
→ (λy.y)          -- apply identity to itself
```

## Church Encodings: Building Everything from Functions

Here's the magic: we can represent data as functions.

### Booleans

```
TRUE  = λx.λy.x    -- returns first argument
FALSE = λx.λy.y    -- returns second argument
```

These aren't just names—they're computational definitions. Watch:

**IF-THEN-ELSE:**
```
IF = λb.λt.λf.b t f

IF TRUE  a b = (λb.λt.λf.b t f) TRUE a b
             = TRUE a b
             = (λx.λy.x) a b
             = a ✓

IF FALSE a b = FALSE a b
             = (λx.λy.y) a b
             = b ✓
```

**Boolean Operations:**
```
AND = λa.λb.a b FALSE
OR  = λa.λb.a TRUE b
NOT = λb.b FALSE TRUE

-- Verify AND TRUE FALSE = FALSE:
AND TRUE FALSE
= (λa.λb.a b FALSE) TRUE FALSE
= TRUE FALSE FALSE
= (λx.λy.x) FALSE FALSE
= FALSE ✓
```

### Natural Numbers (Church Numerals)

Numbers are represented as repeated function application:

```
0 = λf.λx.x           -- apply f zero times
1 = λf.λx.f x         -- apply f once
2 = λf.λx.f (f x)     -- apply f twice
3 = λf.λx.f (f (f x)) -- apply f three times
n = λf.λx.fⁿ x        -- apply f n times
```

**Successor (add 1):**
```
SUCC = λn.λf.λx.f (n f x)

SUCC 2
= (λn.λf.λx.f (n f x)) (λf.λx.f (f x))
= λf.λx.f ((λf.λx.f (f x)) f x)
= λf.λx.f (f (f x))
= 3 ✓
```

**Addition:**
```
ADD = λm.λn.λf.λx.m f (n f x)

-- m f applies f m times, then n f x applies f n more times
-- Total: m + n applications

ADD 2 3
= λf.λx.2 f (3 f x)
= λf.λx.f (f (f (f (f x))))
= 5 ✓
```

**Multiplication:**
```
MULT = λm.λn.λf.m (n f)

-- n f is "apply f n times"
-- m (n f) is "apply (apply f n times) m times" = apply f m×n times

MULT 2 3
= λf.2 (3 f)
= λf.(λx.(3 f)((3 f) x))
= λf.λx.f (f (f (f (f (f x)))))
= 6 ✓
```

### Pairs

```
PAIR  = λa.λb.λf.f a b   -- construct a pair
FIRST = λp.p TRUE        -- extract first element
SECOND = λp.p FALSE      -- extract second element

FIRST (PAIR x y)
= (λp.p TRUE) (PAIR x y)
= (PAIR x y) TRUE
= (λf.f x y) TRUE
= TRUE x y
= x ✓
```

### Lists

```
NIL   = λc.λn.n                    -- empty list
CONS  = λh.λt.λc.λn.c h (t c n)   -- prepend element
HEAD  = λl.l (λh.λt.h) NIL         -- first element
TAIL  = (more complex, uses pairs)
NULL  = λl.l (λh.λt.FALSE) TRUE   -- is list empty?

-- List [1, 2, 3]:
CONS 1 (CONS 2 (CONS 3 NIL))
```

## Recursion: The Y Combinator

Lambda calculus has no built-in recursion (functions are anonymous). But we can derive it!

**The Y Combinator:**
```
Y = λf.(λx.f (x x))(λx.f (x x))
```

This magical function satisfies: `Y g = g (Y g)`

In other words, it finds the **fixed point** of any function.

### How Y Works

```
Y g
= (λf.(λx.f (x x))(λx.f (x x))) g
= (λx.g (x x))(λx.g (x x))
= g ((λx.g (x x))(λx.g (x x)))
= g (Y g)  -- the result contains itself!
```

### Factorial with Y

```
-- Define factorial "template" (takes itself as argument):
F = λself.λn.IF (ISZERO n) 1 (MULT n (self (PRED n)))

-- Actual factorial:
FACT = Y F

FACT 3
= Y F 3
= F (Y F) 3
= F FACT 3                         -- Y F = FACT
= IF (ISZERO 3) 1 (MULT 3 (FACT (PRED 3)))
= IF FALSE 1 (MULT 3 (FACT 2))
= MULT 3 (FACT 2)
= MULT 3 (MULT 2 (FACT 1))
= MULT 3 (MULT 2 (MULT 1 (FACT 0)))
= MULT 3 (MULT 2 (MULT 1 1))
= MULT 3 (MULT 2 1)
= MULT 3 2
= 6 ✓
```

## Lambda Calculus in Ruby

Ruby's lambdas/procs map directly to lambda calculus:

```ruby
# Lambda calculus in Ruby

# Booleans
TRUE  = ->(x) { ->(y) { x } }
FALSE = ->(x) { ->(y) { y } }
IF    = ->(b) { ->(t) { ->(f) { b[t][f] } } }

# Boolean operations
AND = ->(a) { ->(b) { a[b][FALSE] } }
OR  = ->(a) { ->(b) { a[TRUE][b] } }
NOT = ->(b) { b[FALSE][TRUE] }

# Church numerals
ZERO  = ->(f) { ->(x) { x } }
ONE   = ->(f) { ->(x) { f[x] } }
TWO   = ->(f) { ->(x) { f[f[x]] } }
THREE = ->(f) { ->(x) { f[f[f[x]]] } }

SUCC = ->(n) { ->(f) { ->(x) { f[n[f][x]] } } }
ADD  = ->(m) { ->(n) { ->(f) { ->(x) { m[f][n[f][x]] } } } }
MULT = ->(m) { ->(n) { ->(f) { m[n[f]] } } }

# Convert Church numeral to Ruby integer
TO_INT = ->(n) { n[->(x) { x + 1 }][0] }

# Y combinator (Z combinator for strict evaluation)
Z = ->(f) { ->(x) { f[->(y) { x[x][y] }] }[->(x) { f[->(y) { x[x][y] }] }] }

# Factorial
FACT = Z[->(self) {
  ->(n) {
    IF[ISZERO[n]][ONE][->(){ MULT[n][self[PRED[n]]] }[]]
  }
}]

# Test it
puts TO_INT[ADD[TWO][THREE]]  # => 5
puts TO_INT[MULT[TWO][THREE]] # => 6
```

## Lambda Calculus and Programming Languages

Lambda calculus is the theoretical foundation of functional programming:

| Lambda Calculus | Functional Programming |
|-----------------|----------------------|
| λx.body | Anonymous function / lambda |
| f x | Function application |
| λx.λy.body | Curried function |
| β-reduction | Function call |
| Y combinator | Recursion |
| Church numerals | Data encoded as functions |

Languages directly influenced by lambda calculus:
- **Lisp** (1958) - First practical lambda calculus implementation
- **ML** (1973) - Type inference and pattern matching
- **Haskell** (1990) - Pure functional programming
- **Scala, F#, Clojure** - Modern functional languages
- **Ruby, Python, JavaScript** - Lambdas and closures

## Church-Turing Equivalence

Alonzo Church and Alan Turing independently defined computation in 1936. Church used lambda calculus; Turing used his machines. They're equivalent!

**Proof sketch:**
1. Any Turing machine can be simulated by lambda calculus (encode tape as a list, states as functions)
2. Any lambda expression can be evaluated by a Turing machine (implement substitution as tape operations)

This equivalence is the **Church-Turing Thesis**: any "reasonable" definition of computation gives the same class of computable functions.

```
┌─────────────────────┐     ┌─────────────────────┐
│   Lambda Calculus   │ ←→  │   Turing Machines   │
│                     │     │                     │
│  Functions on       │     │  Symbols on tape    │
│  functions          │     │  with read/write    │
└─────────────────────┘     └─────────────────────┘
            ↑                         ↑
            │                         │
            └────────┬────────────────┘
                     │
                     ▼
              ┌──────────────┐
              │  Computation │
              │  (abstract)  │
              └──────────────┘
```

## Reduction Strategies

How do we choose which reduction to perform first?

### Normal Order (Leftmost-Outermost First)
```
(λx.x x)((λy.y) z)
→ ((λy.y) z)((λy.y) z)   -- reduce outer first
→ z((λy.y) z)
→ z z
```

### Applicative Order (Leftmost-Innermost First)
```
(λx.x x)((λy.y) z)
→ (λx.x x) z              -- reduce argument first
→ z z
```

### Why It Matters

**Normal order** always finds the answer if one exists (but may repeat work).
**Applicative order** is more efficient but may loop forever on some terms.

```
-- This term has no normal form (loops forever):
Ω = (λx.x x)(λx.x x)
  → (λx.x x)(λx.x x)
  → (λx.x x)(λx.x x)
  → ...

-- But this should return 42:
(λx.42) Ω

Normal order:  (λx.42) Ω → 42  ✓ (never evaluates Ω)
Applicative:   (λx.42) Ω → (λx.42) Ω → ...  (loops trying to evaluate Ω)
```

This is why Haskell uses **lazy evaluation** (normal order with sharing).

## Lambda Calculus and Hardware

What does lambda calculus have to do with hardware design?

### 1. Combinational Logic as Functions

A combinational circuit is a pure function—no state, output depends only on inputs:

```
-- AND gate in lambda calculus
AND = λa.λb.a b FALSE

-- AND gate in RHDL
behavior do
  y <= a & b
end
```

Both describe the same mapping from inputs to outputs.

### 2. Higher-Order Hardware

HDLs support higher-order concepts:

```ruby
# A function that generates a ripple-carry adder of any width
def make_adder(width)
  Class.new(SimComponent) do
    input :a, width: width
    input :b, width: width
    output :sum, width: width + 1

    behavior do
      sum <= a + b
    end
  end
end

Adder8  = make_adder(8)
Adder16 = make_adder(16)
```

This is **metaprogramming**—functions that generate hardware descriptions.

### 3. Circuit Optimization

Lambda calculus reduction corresponds to circuit optimization:

```
-- Original: (λx.x AND x) a
-- Reduced:  a AND a
-- Further:  a  (since a AND a = a)
```

### 4. Functional Hardware Languages

Some HDLs are directly based on functional programming:

- **Clash** - Haskell to Verilog/VHDL compiler
- **Chisel** - Scala-based HDL (uses functional constructs)
- **Lava** - Haskell embedded HDL

Example in Clash (Haskell-based HDL):
```haskell
-- A parallel prefix adder using higher-order functions
adder :: Signal (Unsigned 8) -> Signal (Unsigned 8) -> Signal (Unsigned 8)
adder = (+)

-- Generate 8 instances
adders = map (uncurry adder) inputs
```

## SKI Combinator Calculus

Lambda calculus can be further simplified to just three combinators:

```
S = λx.λy.λz.x z (y z)   -- "Substitution"
K = λx.λy.x              -- "Konstant" (constant)
I = λx.x                 -- "Identity"
```

**Remarkably, S and K alone are sufficient** (I = S K K).

Any lambda expression can be translated to SKI combinators. This shows that computation requires just two primitive operations!

### SKI to Hardware

SKI combinators map to simple circuits:

```
K: A 2-input multiplexer that always selects input 0
   K x y = x

I: A wire (identity)
   I x = x

S: A more complex routing circuit
   S x y z = (x z) (y z)
```

This suggests a minimal universal computing element.

## Exercises

### Exercise 1: Evaluate by Hand
Reduce to normal form:
```
(λx.λy.x y y)(λa.a)(λb.b)
```

### Exercise 2: Define ISZERO
Define `ISZERO` that returns `TRUE` for Church numeral 0, `FALSE` otherwise:
```
ISZERO 0 = TRUE
ISZERO n = FALSE  (for n > 0)
```

Hint: 0 applies f zero times, so `0 f x = x`.

### Exercise 3: Define PRED (Predecessor)
This is tricky! Define `PRED` such that `PRED n = n - 1` (and `PRED 0 = 0`).

Hint: Use pairs to "shift" values.

### Exercise 4: Implement in Ruby
Implement the `PRED` function from Exercise 3 in Ruby using only lambdas.

## Key Takeaways

1. **Lambda calculus is computation through substitution** - No tape, no state, just function application

2. **Data can be encoded as functions** - Booleans, numbers, lists are all lambda expressions

3. **Recursion emerges from self-reference** - The Y combinator enables infinite computation

4. **Equivalent to Turing machines** - Same computational power, different perspective

5. **Foundation of functional programming** - Ruby's lambdas, Haskell, Lisp all descend from this

6. **Relevant to hardware** - Combinational circuits are pure functions; HDLs use functional concepts

## References

- Church, A. (1936). "An Unsolvable Problem of Elementary Number Theory"
- Barendregt, H. (1984). *The Lambda Calculus: Its Syntax and Semantics*
- Michaelson, G. (2011). *An Introduction to Functional Programming Through Lambda Calculus*
- Pierce, B. (2002). *Types and Programming Languages*
- Peyton Jones, S. (1987). *The Implementation of Functional Programming Languages*
