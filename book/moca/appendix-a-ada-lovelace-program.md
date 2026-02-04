# Appendix A: Ada Lovelace's Bernoulli Number Program

This appendix contains the complete details of Ada Lovelace's 1843 algorithm for computing Bernoulli numbers—widely considered the first computer program ever written.

## What are Bernoulli Numbers?

Bernoulli numbers (B₀, B₁, B₂, ...) are a sequence important in number theory and analysis. They appear in formulas for sums of powers:

```
1¹ + 2¹ + 3¹ + ... + n¹ = n(n+1)/2
1² + 2² + 3² + ... + n² = n(n+1)(2n+1)/6
1³ + 2³ + 3³ + ... + n³ = [n(n+1)/2]²
```

The general formula for the sum of k-th powers involves Bernoulli numbers as coefficients. The first several Bernoulli numbers are:

```
B₀ =  1
B₁ = -1/2   (or +1/2 in some conventions)
B₂ =  1/6
B₃ =  0
B₄ = -1/30
B₅ =  0
B₆ =  1/42
B₇ =  0
B₈ = -1/30
...
```

Note that all odd Bernoulli numbers after B₁ are zero.

## Ada's Original Diagram

Ada wrote her program as a table showing operations, variables, and the state of the machine at each step. This was "Note G" in her translation of Luigi Menabrea's article about Babbage's Analytical Engine.

Here is a reconstruction of her diagram for computing B₇ (which she called B₈, using 1-based indexing):

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                           DIAGRAM FOR THE COMPUTATION OF BERNOULLI NUMBERS                           │
│                                          by A.A.L. (1843)                                            │
├───────┬─────────────┬────────────────────────────────────────────────────────────────────────────────┤
│       │             │                              Variables                                         │
│  Op   │  Operation  ├─────────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┤
│  No.  │             │   V0    │   V1    │   V2    │   V3    │   V4    │   V5    │   V6    │  V7...  │
├───────┼─────────────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┤
│       │  [Initial]  │    1    │    2    │    n    │         │   B1    │   B3    │   B5    │   ...   │
├───────┼─────────────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┼─────────┤
│   1   │  ×          │         │   2n    │         │         │         │         │         │         │
│   2   │  −          │         │  2n-1   │         │         │         │         │         │         │
│   3   │  ÷          │         │(2n-1)/2 │         │         │         │         │         │         │
│   4   │  ×          │         │         │         │  A0     │         │         │         │         │
│   5   │  −          │         │         │  n-1    │         │         │         │         │         │
│   6   │  ×          │         │         │         │         │ A0×B1   │         │         │         │
│   7   │  ÷          │         │         │         │  A1     │         │         │         │         │
│   8   │  −          │         │         │  n-2    │         │         │         │         │         │
│   9   │  ×          │         │         │         │         │         │ A1×B3   │         │         │
│  10   │  ÷          │         │         │         │  A2     │         │         │         │         │
│  ...  │  ...        │         │         │   ...   │   ...   │   ...   │   ...   │   ...   │         │
│  21   │  −          │         │         │         │         │         │         │         │         │
│  22   │  −          │         │         │         │         │         │         │         │         │
│  23   │  −          │         │         │         │         │         │         │         │         │
│  24   │  ÷          │         │         │         │         │         │         │         │   B7    │
│  25   │  +          │         │         │  n+1    │         │         │         │         │         │
└───────┴─────────────┴─────────┴─────────┴─────────┴─────────┴─────────┴─────────┴─────────┴─────────┘

Legend:
  V0-V3   = Working variables for intermediate calculations
  V4-V10  = Storage for previously computed Bernoulli numbers (B₁, B₃, B₅...)
  V11-V13 = Additional intermediate results
  V21-V24 = Constants and loop control variables
  A0, A1  = Coefficients computed during iteration
```

### Key Features of Ada's Notation

**Variable Cards vs Operation Cards:**
Ada distinguished between two types of punched cards:
- **Operation cards**: Specified which operation (+, −, ×, ÷) to perform
- **Variable cards**: Specified which memory locations (V0, V1, ...) to use

**The "Backing" Mechanism:**
Ada's most important insight was the loop. She wrote:

> "Here follows a repetition of Operations 13-23."

This "backing" of the operation cards to repeat a sequence is exactly what we now call iteration.

## The Algorithm Explained

Ada's algorithm computes Bernoulli numbers using the recurrence relation:

```
B_n = -1/(n+1) × Σ(k=0 to n-1) [C(n+1,k) × B_k]
```

Where C(n,k) is the binomial coefficient "n choose k".

### Step-by-Step Breakdown

```
To compute B_n:

1. INITIALIZE
   - Load n into working variable
   - Load previously computed B_0, B_1, ... B_(n-1) into memory

2. COMPUTE COEFFICIENTS (the A values)
   - A_0 = (2n-1)/(2) × (something involving n)
   - A_1 = A_0 × (n-1)/(2×2)
   - A_2 = A_1 × (n-2)/(2×3)
   - ... (this is the inner loop)

3. ACCUMULATE SUM
   - sum = A_0×B_1 + A_1×B_3 + A_2×B_5 + ...

4. COMPUTE RESULT
   - B_n = -sum / (n+1)

5. STORE AND REPEAT
   - Store B_n for use in computing B_(n+2)
   - Increment n by 2 (skip odd indices)
   - GOTO step 2 (this is the outer loop)
```

## Modern Pseudocode Translation

```
function compute_bernoulli_numbers(max_n):
    # Initialize array with known values
    B[0] = 1
    B[1] = -1/2

    # Outer loop: compute each Bernoulli number
    for n from 2 to max_n:
        # Odd Bernoulli numbers (except B_1) are zero
        if n is odd:
            B[n] = 0
            continue

        # Inner loop: compute the sum using recurrence
        sum = 0
        for k from 0 to n-1:
            # Compute binomial coefficient C(n+1, k)
            coeff = binomial(n+1, k)

            # Accumulate: coeff × B[k]
            sum = sum + coeff × B[k]

        # Final division
        B[n] = -sum / (n + 1)

    return B

function binomial(n, k):
    # Compute "n choose k"
    result = 1
    for i from 1 to k:
        result = result × (n - k + i) / i
    return result
```

## Ruby Implementation

Here is Ada's algorithm translated to executable Ruby code:

```ruby
# Ada Lovelace's Bernoulli Number Algorithm (1843)
# Translated to Ruby, 180 years later
#
# This code computes the same values Ada's program would have
# computed on Babbage's Analytical Engine—had it been built.

def bernoulli_numbers(count)
  # Use Rational for exact arithmetic (no floating-point errors)
  # The Analytical Engine used decimal, but the principle is the same
  b = [Rational(1, 1)]  # B₀ = 1

  (1...count).each do |n|
    # Compute B_n using the recurrence relation:
    # B_n = -Σ(k=0 to n-1) [C(n+1,k) × B_k] / (n+1)

    sum = Rational(0, 1)

    (0...n).each do |k|
      # This inner loop is what Ada called "backing"
      # The operation cards would physically reverse to repeat
      coeff = binomial(n + 1, k)
      sum += coeff * b[k]
    end

    b[n] = -sum / (n + 1)
  end

  b
end

def binomial(n, k)
  # Compute binomial coefficient "n choose k"
  # This was done by repeated multiplication and division
  return 1 if k == 0 || k == n
  (1..k).reduce(Rational(1, 1)) { |acc, i| acc * (n - k + i) / i }
end

# Execute the algorithm
if __FILE__ == $0
  puts "Ada Lovelace's Bernoulli Number Algorithm"
  puts "=" * 45
  puts

  result = bernoulli_numbers(12)

  result.each_with_index do |b, i|
    # Format as fraction for exact display
    if b != 0
      printf "B_%2d = %s\n", i, b.to_s
    end
  end

  puts
  puts "Note: B_n = 0 for all odd n > 1"
end
```

**Output:**
```
Ada Lovelace's Bernoulli Number Algorithm
=============================================

B_ 0 = 1
B_ 1 = -1/2
B_ 2 = 1/6
B_ 4 = -1/30
B_ 6 = 1/42
B_ 8 = -1/30
B_10 = 5/66

Note: B_n = 0 for all odd n > 1
```

## RHDL Hardware Implementation

For comparison, here's how you might implement a Bernoulli number calculator in hardware using RHDL. This shows how the same algorithm maps to sequential hardware:

```ruby
# A hardware Bernoulli number calculator
# This demonstrates Ada's algorithm in synthesizable hardware
#
# Note: This is simplified - real hardware would need:
# - Fixed-point or floating-point arithmetic units
# - Proper bit widths for the range of values
# - Pipeline stages for the multiplier/divider

class BernoulliCalculator < SimComponent
  input :clk
  input :reset
  input :start                    # Pulse to begin computation
  input :n, width: 8              # Which Bernoulli number to compute

  output :result, width: 32       # The result (fixed-point)
  output :done                    # Computation complete flag

  # Internal state
  wire :state, width: 3
  wire :k, width: 8               # Inner loop counter
  wire :sum, width: 32            # Accumulator
  wire :coeff, width: 32          # Current binomial coefficient

  # State machine states
  IDLE    = 0
  INIT    = 1
  COMPUTE = 2  # Inner loop: accumulate sum
  DIVIDE  = 3  # Final division
  DONE    = 4

  behavior do
    if reset == 1
      state <= IDLE
      done <= 0
    elsif rising_edge(clk)
      case state
      when IDLE
        if start == 1
          state <= INIT
          k <= 0
          sum <= 0
        end

      when INIT
        # Load initial coefficient
        coeff <= 1  # C(n+1, 0) = 1
        state <= COMPUTE

      when COMPUTE
        # Inner loop: sum += coeff * B[k]
        # (B[k] would come from a lookup table or memory)
        sum <= sum + coeff * b_lookup(k)

        # Update coefficient: C(n+1,k+1) = C(n+1,k) * (n+1-k) / (k+1)
        coeff <= coeff * (n + 1 - k) / (k + 1)

        k <= k + 1
        if k == n - 1
          state <= DIVIDE
        end

      when DIVIDE
        # B[n] = -sum / (n + 1)
        result <= -sum / (n + 1)
        state <= DONE

      when DONE
        done <= 1
        if start == 0
          state <= IDLE
          done <= 0
        end
      end
    end
  end
end
```

## The First Bug

Historians examining Ada's notes have found what may be the first documented computer bug. In one version of her table, there's an error:

```
Original (incorrect):  V4 ÷ V5
Corrected:            V5 ÷ V4
```

The operands are reversed. Whether this was:
- Ada's mathematical error
- A transcription error by the printer
- An error introduced by Babbage in review

...is still debated. But it shows that even the first program had bugs—a tradition that continues to this day.

## Historical Context

**Publication:** 1843, in "Sketch of the Analytical Engine" (translation of Luigi Menabrea's article, with extensive notes by A.A.L.)

**Note G:** Ada's notes were labeled A through G. Note G contained the Bernoulli algorithm and was by far the longest, demonstrating her deep understanding of the machine's capabilities.

**Recognition:** Ada signed her notes only as "A.A.L." (Augusta Ada Lovelace). Her contribution wasn't widely recognized until the 20th century. The programming language Ada (1980) was named in her honor.

## Why This Program Matters

Ada's Bernoulli algorithm demonstrates that she understood:

1. **Stored program concept** - The algorithm exists independently of the hardware
2. **Variables and memory** - Named storage locations (V0, V1, V2...)
3. **Iteration** - Loops via "backing" of operation cards
4. **Nested loops** - Outer loop over n, inner loop over k
5. **Conditional execution** - Different paths based on values
6. **Subroutines** - Reusable sequences of operations

These are the fundamental concepts of programming. Ada discovered them in 1843, over a century before electronic computers existed.

As she wrote:

> "The Analytical Engine weaves algebraical patterns just as the Jacquard loom weaves flowers and leaves."

The patterns haven't changed. Only the speed of the loom.

## References

- Lovelace, A.A. (1843). "Notes by the Translator" in *Sketch of the Analytical Engine Invented by Charles Babbage*
- Menabrea, L.F. (1842). "Notions sur la Machine Analytique de M. Charles Babbage"
- Toole, B.A. (1992). *Ada, the Enchantress of Numbers*
- Swade, D. (2001). *The Difference Engine: Charles Babbage and the Quest to Build the First Computer*
