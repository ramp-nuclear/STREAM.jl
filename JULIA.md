# JULIA.md

> **Instructions for Claude Code.** Read this file at the start of every Julia coding session. It is a set of imperative rules. When rules conflict with one another, the order of priority is: (1) correctness, (2) type stability and performance, (3) consistency with the surrounding codebase, (4) the rules below. Never silently violate a rule — if you must, leave a one-line comment explaining why.

---

## 0. General Code-Quality Rules (Read First)

These apply to **all** code you write and override the stylistic rules below whenever they conflict.

- **Do only what was asked.** Implement the simplest thing that satisfies the request. Do not add features, configuration options, abstraction layers, or "flexibility" nobody requested. Speculative generality is a defect, not a courtesy.
- **Match the existing codebase first.** Before writing, read neighboring files and follow their naming, structure, formatting, and patterns. Where surrounding code conflicts with this guide on a *stylistic* point, match the surrounding code (not on a correctness or performance point).
- **Produce minimal diffs.** Touch only the code the task requires. Never reformat, re-indent, reorder, or "improve" unrelated code. Never rename or move things outside the scope of the task.
- **Comment _why_, not _what_.** A comment is justified only when the code cannot speak for itself: a non-obvious decision, a workaround, an external constraint, or a subtle invariant. Never restate what the code plainly does (`x += 1  # increment x` is forbidden). If code needs a comment to be understood, first try to make it clearer (better names, smaller functions), then comment only what remains genuinely non-obvious.
- **No narration comments.** Do not write step-by-step comments that describe the next line (`# First, validate the input`, `# Now loop over the items`, `# Return the result`).
- **Leave no scaffolding.** Delivered code contains no leftover debug `println`/`@show`, no commented-out code, no placeholder stubs, and no `# TODO: implement` standing in for a real implementation.
- **No decorative output.** No emoji, no ASCII-art banners, no large comment "divider walls." (See §19 for the limited, sanctioned use of section comments.)
- **Do not reinvent the standard library.** Use `Base` and the stdlib (`maximum`, `sum`, `unique`, `sort`, `findfirst`, `mapreduce`, etc.) instead of hand-rolling equivalents.
- **Do not invent APIs.** Only call functions, methods, and packages you know exist. If you are unsure whether a name or signature is real, verify it against the source or docs rather than guessing a plausible-sounding one.
- **Avoid the boolean trap.** A bare boolean positional argument (`process(data, true)`) is unreadable at the call site. Use a keyword argument (`process(data; sorted=true)`), an `@enum`, or dispatch instead.
- **Do not over-handle errors.** Add input validation and `try`/`catch` only where a real, expected failure mode warrants it. Never wrap code in broad `try`/`catch` that swallows or masks errors.
- **Verify before claiming done.** When you can run the code or tests, do so and confirm it works before reporting completion. Do not assert that untested code is correct.
- **Tests must assert real behavior.** No tautological tests (`@test true`), no tests that only exercise a mock. Test the actual contract and meaningful edge cases.
- **No unprompted entrypoints.** Do not add `main()` functions, `if abspath(PROGRAM_FILE) == @__FILE__ … end` blocks, example-usage dumps, or file-level license/banner headers unless explicitly asked.
- **Domain guides supplement this file.** A project may provide additional package-specific guides (e.g. for a particular modeling or data framework). Follow them *in addition* to these rules; they take precedence on package-specific API usage, this file governs general Julia.

---

## 1. File, Package, and Project Layout

- **Do** put all real code inside a package, even small projects. Only one-off REPL scripts may live outside a package.
- **Do** place source files under `src/` and tests under `test/`. The main module file is `src/<PackageName>.jl`.
- **Do** mirror the source tree in tests: tests for `src/foo.jl` go in `test/foo.jl`.
- **Do** use `Project.toml` (and `Manifest.toml` only where appropriate, e.g. apps not libraries). Declare `[compat]` for every dependency; specify versions without a leading caret (write `"0.17"`, not `"^0.17"`).
- **Do** end source filenames with `.jl`. GitHub repo names end with `.jl`; the package name itself does **not** end with `.jl`.
- **Do** ensure every file ends with a trailing newline character.
- **Never** commit trailing whitespace.
- **Build file paths with `joinpath` and `@__DIR__`**, never bare relative strings. Code that reads a data file must work regardless of the current working directory: `joinpath(@__DIR__, "..", "data", "x.csv")`, not `"data/x.csv"`. Use `pkgdir(MyPackage)` to locate package-relative resources.

## 2. Module Structure and Imports

- **Do** put exactly one `module … end` per file at the top of the file. Code in a top-level module block is **not** indented. Only indent the body of *sub*modules declared mid-file.
- **Do** put module imports at the top of the file (or immediately after a `module` declaration), in this order separated by blank lines:
  1. `import` statements (only if absolutely required), grouped together.
  2. `using` statements.
- **Do** sort imports alphabetically. Relative imports precede absolute imports.
- **Do** one package per line:
  ```julia
  using A
  using B
  ```
  Never `using A, B` on the same line.
- **Do** prefer `using` over `import`. Use explicit `using Pkg: name1, name2` form in packages so that extension of methods is always explicit. To extend, qualify the name:
  ```julia
  Base.length(x::MyType) = ...   # good
  ```
  Never use `import Base: length` to enable bare `length(x::MyType) = ...`.
- **Do** group explicit imports as: modules, constants, types, macros, functions — each group sorted alphabetically.
- **Do** wrap long explicit-import lines either with line continuation (indent one level) or by using multiple `using Pkg:` lines for the same package.
- **Never** use `importall`.
- **Never** put module imports inside a file loaded by `include`. Hoist them to the top of the including file.
- **Do** write qualified macro calls as `Module.@macro_name`, never `@Module.macro_name`.

## 3. Exports

- **Do** export every name that is part of your public API. Document everything you export.
- **Do** place all `export` statements at the top of the main module file, right after imports.
- **Do** prefer one `export` per line; or group related names on a single `export` line. Never split a single `export` across multiple lines.
- **Don't** export everything — exporting is a curated public-API decision. Internal helpers may still be documented and called by users via `Module.name`, but should not be exported.
- **Do** prefix internal-only names with a leading underscore (`_helper`, `_INTERNAL_CONST`, `_MyInternalType`) to signal "no API stability guarantee."

## 4. Naming Conventions (mandatory)

- **Modules and types (including abstract types and structs):** `UpperCamelCase` (`SparseArrays`, `UnitRange`, `MyType`). All-caps for acronyms used as identifiers (`GLM`, not `Glm`).
- **Functions and variables:** `lowercase` or `snake_case`. Prefer squashed (`isequal`, `haskey`, `indexin`) when the word boundary is unambiguous; use underscores when readability would otherwise suffer. When in doubt, use `snake_case`.
- **Constants:** `SCREAMING_SNAKE_CASE` (`const DEFAULT_VAL = 0`, `const MAX_ITERS = 100`).
- **`const` type aliases:** `UpperCamelCase` (`const FloatVec = Vector{Float64}`).
- **Mutating functions:** append `!` (e.g. `sort!`, `push!`, `fill!`). The first mutated argument comes first in the parameter list.
- **Abstract types:** begin with `Abstract` (`AbstractArray`, `AbstractPolygon`).
- **Predicate functions** (returning `Bool`) read as a question: prefix with `is`/`has`/`can` or use an adjective (`isempty`, `iseven`, `haskey`, `isvalid`). They return a `Bool`, never a truthy sentinel.
- **Type parameters:** single uppercase letters that relate to the meaning:
  - `T` — generic element/value type.
  - `N` — numeric type or dimensionality.
  - `S` — secondary type.
  - For domain-specific code, follow project conventions (e.g. JuliaReach uses `VN` for vectors of numeric type `N`, `MN` for matrices, `S` for set types).
- **Internal helpers:** leading underscore (`_compute_step`, `_MyInternalType`, `_MY_CONST`).
- **Avoid abbreviations.** Prefer whole words over single letters except for mathematical entities where the letter *is* the convention (e.g. `*(a::AbstractMatrix, b::AbstractMatrix)`).
- **Function names describe an action or property, not the type.** Write `submit(bid::Bid)`, not `submit_bid(bid)`. Write `bids(batch::Batch)`, not `bids_in_batch(batch)`.
- **Never** alter the case of identifiers when quoting them in comments or docs.

## 5. Indentation, Line Length, Whitespace

- **Do** use **4 spaces** per indentation level. **Never** use tabs.
- **Target line length: 92 characters.** Treat it as a soft maximum; small overruns are acceptable when breaking would harm readability.
- **Do** include exactly one space after every comma and semicolon. Never put space before a comma or semicolon.
  ```julia
  x[1, 2]          # good
  x[1,2]           # bad
  x[1 , 2]         # bad
  ```
- **Do** put a single space around binary operators: `=`, `==`, `<`, `>`, `+=`, `->`, `&&`, `||`, `+`, `-`, `*`, `/`, etc.
- **Don't** put spaces around these "tight" operators:
  - `^` (exponentiation): `x^2`, not `x ^ 2`.
  - `:` (range): `1:n`, `ham[1:9]`. Use parentheses for clarity with mixed expressions: `1:(n - 1)`, never `1:n - 1`.
  - `//` (rational): `1//2`.
  - `<:` and `>:` **inside type parameter lists**: `Vector{T<:Real}`. Outside type parameter lists (as binary operators), they take normal spaces: `T <: Real`.
  - Unary operators against their operand: `-1`, `!flag`, never `- 1` or `! flag`.
- **Keyword arguments: do NOT put spaces around `=`.**
  ```julia
  foo(x; y=3, prefix="")         # good
  foo(x; y = 3, prefix = "")     # bad
  ```
  This also applies to default values in signatures and `NamedTuple` fields:
  ```julia
  xy = (x=1, y=2)                # good
  xy = (x = 1, y = 2)            # bad
  ```
- **Always** separate positional arguments from keyword arguments with `;` at call sites:
  ```julia
  foo(x; y=3)         # good
  foo(x, y=3)         # tolerated but discouraged
  ```
- **Don't** pad brackets/parens with spaces: `Int64(value)`, not `Int64( value )`.
- **Don't** vertically align consecutive assignments by padding spaces around `=`:
  ```julia
  # bad
  x             = 1
  long_variable = 3

  # good
  x = 1
  long_variable = 3
  ```
- **Do** group related one-line statements together with no blank lines between them; separate logical groups with one blank line.
- **Do** separate top-level definitions with one blank line. Long-form function definitions should be preceded and followed by exactly one blank line.
- **Don't** add a blank line immediately after `function …` or immediately before `end`.
- **Never** put two consecutive blank lines anywhere.
- **Do** insert a blank line between a control-flow block and the function's `return`:
  ```julia
  function foo(bar; verbose=false)
      if verbose
          println("baz")
      end

      return bar
  end
  ```

## 6. Numbers, Conversions, and Numerical Correctness

### Literals
- **Do** always include leading and trailing zeros on floats: `0.1`, `2.0`, `3.0f0`. Never `.1`, `2.`, `3.f0`.
- **Do** prefer `Int` literals in generic numeric code so the literal does not force promotion of the caller's type. Write `2 * x`, not `2.0 * x`, unless you specifically need `Float64` arithmetic.
- **Do** use `oneunit(x)` / `zero(x)` / `oftype(x, y)` for type-preserving literal-like values inside generic functions.
- **Do** initialize `BigFloat` from a string literal (`BigFloat("0.1")`), never from a `Float64` literal (`BigFloat(0.1)` loses precision).

### Conversion and rounding
- **Use `round(Int, x)`** to round-and-convert in one step, never `Int(round(x))` or `convert(Int, round(x))`. Likewise `floor(Int, x)`, `ceil(Int, x)`, `trunc(Int, x)`.
- **Use `parse(T, str)`** for string→number conversion, and `tryparse(T, str)` (returns `nothing` on failure) when the input may be malformed.
- **`T(x)` constructs/converts with possible representation change; `convert(T, x)`** is the lossless-conversion path used implicitly by assignment and `setindex!`. Inside generic code prefer `convert`/`oftype` to keep types flowing from inputs.
- **`/` always returns a float**, even on integers (`4 / 2 === 2.0`). Use `÷` / `div` for integer (truncating) division and `//` for exact rationals.

### Numerical correctness (mandatory in numeric code)
- **`Int` arithmetic overflows silently** — `typemax(Int) + 1` wraps to a negative number with no error. When inputs can be large (factorials, combinatorics, accumulators, sizes), use `widen`, `Int128`/`BigInt`, or the `Base.Checked` functions (`checked_add`, `checked_mul`).
- **Use numerically stable primitives instead of naive arithmetic:**
  - `hypot(a, b)` instead of `sqrt(a^2 + b^2)` (avoids overflow/underflow).
  - `log1p(x)` / `expm1(x)` instead of `log(1 + x)` / `exp(x) - 1` near zero.
  - `muladd(a, b, c)` / `fma(a, b, c)` in inner kernels for a fused, more accurate, often faster multiply-add.
  - `evalpoly(x, coeffs)` for polynomial evaluation (Horner's method) instead of summing powers.
- **Guard floating-point edge cases** with `isnan`, `isinf`, `isfinite` rather than equality tests against `NaN`/`Inf` (`x == NaN` is always `false`).

## 7. Type System Usage

### General philosophy
- **Default to generic, abstract type annotations on function arguments.** Annotate only as tightly as you need for dispatch or correctness; annotate as loosely as you can for genericity.
  ```julia
  splicer(arr::AbstractArray, step::Integer) = arr[begin:step:end]      # good
  splicer(arr::Array{Int}, step::Int) = arr[begin:step:end]             # bad
  ```
- **You may omit argument type annotations entirely** on small, obvious helpers. Otherwise annotate to the most general abstract type that captures the intended interface; use tight annotations only for dispatch.

### Struct fields — opposite philosophy
- **Use concrete (or parametric-concrete) types for struct fields**, never abstract types. Abstract field types kill performance because the compiler cannot infer layout.
  ```julia
  # bad — abstract field, slow
  struct MyType
      a::AbstractFloat
  end

  # good — parametric, concrete at instantiation
  struct MyType{T<:AbstractFloat}
      a::T
  end
  ```
- **Do** parameterize containers concretely: `a::Vector{Float64}` or `a::A where A<:AbstractVector`, never bare `a::Array` or `a::AbstractVector`.
- **For function-valued fields**, use a type parameter `F` (do **not** annotate `::Function`, which is abstract).
- **If a field will genuinely hold heterogeneous values**, explicitly annotate it `::Any` rather than leaving it untyped — make the intent explicit.
- **Mutability:** use `struct` (immutable) by default. Use `mutable struct` only when you genuinely need to mutate fields after construction.

### Parametric and where-clauses
- **Don't** introduce static parameters you don't use:
  ```julia
  foo(x::T) where {T<:Real} = ...   # bad if T is not used in body
  foo(x::Real) = ...                # good
  ```
- **Do** always enclose `where` bindings in braces: `f(x) where {T} = ...`, never `f(x) where T = ...`.
- **Avoid** dispatching on type parameters when you don't own the method or the parameterized type (likely type piracy).
- **Use** `<:` and `isa` for type tests, never `==` on types (except comparing to a known concrete type like `T == Float64`).

### Abstract vs concrete
- **Never** create containers with abstract element types when concrete will do. `Float64[]` is far better than `Real[]`. If you genuinely need heterogeneity, use `Vector{Any}` (faster than `Vector{Real}`).
- **Never** use strange `Union`s like `Union{Function, AbstractString}` — that signals a design problem. (Small unions like `Union{T,Nothing}` are fine; see §16.)

### Enumerations
- **For a fixed set of named values, use the `@enum` macro** rather than an abstract type hierarchy or magic integers/symbols:
  ```julia
  @enum Direction north east south west
  ```
  Use `@enum` when the values are a closed set with no associated data. Use dispatch on singleton types only when each value needs distinct *method behavior*.

### Memory layout (`isbits`, heap vs stack)
- **Design small structs to be `isbits`:** immutable, with every field a concrete bits-type (`Int`, `Float64`, other `isbits` structs, `Tuple`s of these). Then `Vector{T}` is a flat, contiguous, cache-friendly buffer with no pointer indirection, and instances stack-allocate (effectively free). Verify with `isbitstype(T)`.
- **Heap vs stack mental model:** immutable structs, tuples, and `StaticArrays` stack-allocate or live inline; `Array` and `mutable struct` heap-allocate. A `mutable struct` field or an abstractly-typed field forces boxing and pointer chasing — avoid both in hot data structures.
- **Use `Tuple` / `NamedTuple` for small, fixed, heterogeneous data** (stack-allocated, fully type-stable) instead of `Vector{Any}` or a `Dict`. Use `NamedTuple` when the fields deserve names.
- **For hot numeric loops, prefer struct-of-arrays (SoA) over array-of-structs (AoS):** iterating `xs::Vector{Float64}, ys::Vector{Float64}` vectorizes far better than `Vector{Point}`. Reach for `StructArrays.jl` to keep an AoS *interface* over SoA *storage* when both ergonomics and speed matter.

## 8. Multiple Dispatch Idioms

- **Do** prefer many small methods over one big function full of `isa` / `if typeof(x) == ...` branches:
  ```julia
  # bad
  function mynorm(A)
      if isa(A, Vector); return sqrt(real(dot(A, A))); end
      if isa(A, Matrix); return maximum(svdvals(A)); end
      error("invalid")
  end

  # good
  mynorm(x::Vector) = sqrt(real(dot(x, x)))
  mynorm(A::Matrix) = maximum(svdvals(A))
  ```
- **Do** order method definitions from least specific to most specific.
- **Use dispatch constraints for dispatch, not for documentation.** Don't artificially narrow argument types just to "document" what the function expects.
- **Don't** abuse value-as-parameters (`Car{:Honda, :Accord}`) unless you do heavy compile-time-specialized work per type, the set of types is small, and you process homogeneous collections of them.
- **Don't** write a trivial wrapper anonymous function for a named function. Write `map(f, a)`, never `map(x -> f(x), a)`.
- **In method signatures, omit names for unused arguments.** Write `f(::Number, y) = y`, not `f(x::Number, y) = y`.

## 9. Type Stability (mandatory)

A function is **type-stable** if its return type depends only on the types of its inputs (not their values), and if every local variable holds a single concrete type throughout its lifetime. **Type stability is the single biggest performance lever in Julia.**

- **Do** ensure every function returns a value whose type is determined by the input types.
  ```julia
  pos(x) = x < 0 ? 0 : x          # bad — returns Int or x's type
  pos(x) = x < 0 ? zero(x) : x    # good — returns typeof(x)
  ```
- **Do not** change the type of a local variable inside a function. If you start with `x = 0` and later do `x /= 2.0`, you've made `x` type-unstable. Initialize as `x = 0.0`, or use `x::Float64 = 0`, or restructure the loop.
- **Do** use `@code_warntype` (or `JET.jl`) to verify. Any red type (a `Union`, `Any`, or non-concrete type) in the output is a problem.
- **For functions whose output type depends on a runtime value**, use the **function-barrier pattern**: do the unstable setup in an outer function, then call a kernel function with concrete arguments so the kernel is fully specialized.
- **For untyped slots** (e.g. `Vector{Any}` element access, parsed config), annotate at the use site: `x = a[1]::Int32`.
- **Captured variables** inside closures get boxed; if a closure is hot, either annotate the captured variable (`r::Int = r0`) or wrap the closure in a `let` block.

## 10. Performance Patterns

### Globals
- **Never** read mutable global variables from inside performance-critical code. Pass them as arguments.
- **Do** declare globals `const`. If the value must change, annotate the global's type: `global x::Vector{Float64} = rand(1000)`.
- **Never** use the `global` keyword to mutate module-level state from inside a function in hot code. Pass state as arguments and return updated values.

### Building collections
- **Prefer a comprehension, `map`, or generator over a `push!`-in-a-loop** when the result can be expressed that way — it is clearer and lets the compiler infer the element type and size.
  ```julia
  ys = [f(x) for x in xs]          # good
  ys = map(f, xs)                  # good
  # avoid:
  ys = []                          # untyped, abstract eltype
  for x in xs
      push!(ys, f(x))
  end
  ```
- **When you consume the result only once** (e.g. feeding a reduction), use a generator (no brackets) to avoid the intermediate array:
  ```julia
  total = sum(x^2 for x in xs)     # good — no temporary array
  total = sum([x^2 for x in xs])   # wasteful — allocates then discards
  ```
- **When `push!` in a loop is genuinely necessary** (output size is conditional/unknown), declare the element type and `sizehint!` if you know the approximate final length:
  ```julia
  ys = Float64[]
  sizehint!(ys, length(xs))
  for x in xs
      x > 0 && push!(ys, sqrt(x))
  end
  ```
- **Use** `filter` / `mapreduce` / `reduce` instead of manual accumulation loops where they read clearly. Prefer `reduce(vcat, parts)` over repeated concatenation in a loop.
- **Allocate with the correct element type** using `zeros(T, n)`, `ones(T, n)`, `fill(v, n)`, or `similar(x)` — never build via untyped `[]` and push.

### Allocations and broadcasting
- **Do** preallocate outputs and pass them in. Provide a mutating `f!(out, args...)` variant alongside any allocating `f(args...)` where allocation cost matters.
- **Do** prefer `@views` (or explicit `view`) over slicing whenever you only read or do a few operations on the slice — slicing copies, views don't:
  ```julia
  @views s = sum(x[2:end-1])
  ```
- **Do** use broadcasting and fuse dot operations to eliminate temporaries:
  ```julia
  @. y = 3*x^2 + 4*x + 7*x^3
  ```
- **Do** use `.=` for in-place assignment into preallocated arrays.
- **Do** consider `StaticArrays.jl` (`SVector`, `SMatrix`) for small (< ~100 element) fixed-size vectors and matrices.
- **Don't** call `sum([x, y, z])`. Call `x + y + z`.
- **Use** `abs2(z)` instead of `abs(z)^2`; `div`/`fld`/`cld` for integer division.

### In-place operations and zero-allocation discipline
- **Treat zero allocations as the target for hot inner loops.** Measure with `@allocated expr` or the alloc count from `BenchmarkTools.@btime`; a hot loop that allocates per iteration is a defect to fix, not a detail.
- **Use the in-place LinearAlgebra API** instead of operators that allocate fresh outputs in numeric code:
  - `mul!(C, A, B)` (5-arg `mul!(C, A, B, α, β)` for `C = α·A·B + β·C`) instead of `C = A * B`.
  - `ldiv!` / `lu!` / `cholesky!` for in-place solves and factorizations.
  - `lmul!` / `rmul!` for in-place scaling, `axpy!(α, x, y)` for `y .+= α .* x`.
  - `copyto!(dest, src)` / `copy!` instead of `dest = copy(src)` when `dest` already exists.
- **Reuse buffers across iterations** rather than reallocating inside a loop. Allocate once outside, then write into the buffer with `.=`, `mul!`, `copyto!`, etc.

### Memory order and iteration
- **Julia arrays are column-major.** Iterate with the inner loop over the first index: `for j in axes(A, 2), i in axes(A, 1)`.
- **Use** `eachindex(A)` or `LinearIndices(A)` to iterate, not `1:length(A)` (it's wrong for offset arrays and may segfault under `@inbounds`).
- **Use** `for i in 1:n`, never `for i = 1:n` (also in comprehensions: `[f(x) for x in xs]`).

### Generic, index-agnostic code
- **Do not assume 1-based indexing or a concrete element type.** Code written only for `Vector{Float64}` starting at index 1 silently breaks on `OffsetArrays`, `view`s, GPU arrays, and other `AbstractArray`s.
- **Iterate and index generically:** use `eachindex(A)`, `axes(A, d)`, `firstindex(A)`/`lastindex(A)`, and `begin`/`end` in indexing — never hardcoded `1` or `length(A)`.
- **Allocate results that match the input:** `similar(A)`, `zero(eltype(A))`, `one(eltype(A))`, `fill!(similar(A), x)`.
- **Compute output element types from inputs** with `eltype` and `promote_type` so generic numeric functions stay type-stable across argument types:
  ```julia
  T = promote_type(eltype(a), eltype(b))
  out = similar(a, T)
  ```

### Compile latency and invalidations
- **Type piracy and abstractly-typed `const` globals trigger method invalidations**, inflating time-to-first-execution across the whole session. Avoiding piracy (§11) and concretely typing globals (above) is a latency concern as well as a correctness one.
- **For libraries where startup latency matters,** add a `PrecompileTools.@compile_workload` block exercising the main entry points so representative methods are precompiled. Do not add this speculatively to small internal packages.

### Performance annotations (use with care)
- **`@inbounds`** disables bounds checks. Use only when you can prove indices are in bounds.
- **`@simd`** promises loop iterations are independent and reorderable; place it immediately before the `for`.
- **`@fastmath`** allows non-IEEE reorderings. Never use on code that relies on `NaN` semantics or strict associativity.

### Other
- **Don't** use string interpolation for I/O. Write `println(file, a, " ", b)`, not `println(file, "$a $b")`. (See §17.)
- **For error/deprecation messages** built from runtime values, use `LazyString` / `lazy"…"`.
- **Don't** profile a function on its first call (you'll measure compilation). Use `BenchmarkTools.@btime` / `@benchmark`.

## 11. Function Design

### Form
- **Short-form (`f(x) = expr`)** only when the entire definition fits on one line.
- **Long-form (`function f(x) … end`)** otherwise. For multi-line bodies, **always** use long form.
- **Use short form** for trivial constructors, aliases, and unit-style definitions (e.g. `×(X, Y) = CartesianProduct(X, Y)`).
- **Stub definitions:** single-line: `struct Foo <: AbstractFoo end`, `function foo end`.

### `return` statements
- **In long-form definitions, always** write an explicit `return`, even `return nothing`.
- **In short-form definitions, omit** `return`.
- **Always return an explicit value.** Write `return nothing` if there's nothing to return. Never write a bare `return`.

### Multiple return values and destructuring
- **Return multiple values as a tuple**, and destructure at the call site:
  ```julia
  minmax_vals(xs) = (minimum(xs), maximum(xs))
  lo, hi = minmax_vals(xs)
  ```
- **Use property destructuring** for named fields / `NamedTuple`s / config-like structs:
  ```julia
  (; lo, hi) = bounds          # binds lo = bounds.lo, hi = bounds.hi
  ```
- **Use `first`, `last`, and `only`** instead of `x[1]`, `x[end]`, and `x[1]`-with-an-assumption. `only(xs)` asserts exactly one element and is self-documenting.
- **Prefer returning a `NamedTuple`** over a positional tuple when there are several values whose meaning isn't obvious from order.

### Argument ordering (follow Julia Base conventions)
1. Function argument (enables `do`-block syntax).
2. `IO` stream.
3. Input being mutated.
4. Type (for output-type-specifying calls).
5. Input not being mutated.
6. Key (for indexed/associative collections).
7. Value.
8. Other positional arguments.
9. Varargs.
10. Keyword arguments.

Exceptions: `convert` puts type first always; `setindex!` puts value before indices so indices can be varargs.

### Keyword arguments
- **Do** use keyword arguments for optional configuration with sensible defaults.
- **Do** at call sites, separate keywords from positionals with `;`.
- **Don't** put spaces around `=` in keyword arguments (see §5).

### Multi-line signatures (canonical layout)
If the full signature does not fit in 92 chars, put **all** positional args (and optionally all keyword args) on their own lines, one per line, indented one level; the closing `)` aligns with the `function` keyword:
```julia
function foobar(
    df::DataFrame,
    id::Symbol,
    variable::Symbol,
    value::AbstractString,
    prefix::AbstractString="",
)
    # body
end
```
- **Do** include the trailing comma after the last argument when args are on separate lines.
- **Don't** indent two levels and **don't** mix some args on the open-paren line with others below.

### `do`-blocks
- **Do** use `do`-blocks where the first argument is a function with a multi-line body (`open`, `map`, `filter`). Don't wrap a single-name function in `f -> do … end` — pass it directly.

### Constructors
- **Constructors named `T(...)` must return a value of type `T`.** Use a different function name if you need different behavior.
- **Use an inner constructor (with `new`)** only to enforce invariants or to build objects that cannot otherwise be constructed. Keep inner constructors minimal; put convenience logic in outer constructors.
  ```julia
  struct Interval
      lo::Float64
      hi::Float64
      function Interval(lo, hi)
          lo <= hi || throw(ArgumentError("lo must be <= hi"))
          return new(lo, hi)
      end
  end
  ```
- **Use `Base.@kwdef`** for structs that benefit from keyword construction and field defaults instead of writing boilerplate outer constructors:
  ```julia
  Base.@kwdef struct Config
      iters::Int = 100
      tol::Float64 = 1e-8
      verbose::Bool = false
  end
  ```

### Anti-patterns to avoid
- **Don't** parenthesize `if` / `while` conditions: write `if a == b`, not `if (a == b)`.
- **Don't** overuse `...` splatting. `[a; b]` concatenates better than `[a...; b...]`; `collect(a)` is better than `[a...]`.
- **Don't** overuse `try`/`catch`. Validate inputs and use proper control flow.
- **Don't** overuse macros. If a macro's body can be a function, make it a function. Calling `eval` inside a macro is a strong code smell.
- **Don't** expose unsafe ops at the interface level (`getindex` calling `unsafe_load`).
- **Don't** overload methods on Base container types like `show(::IO, ::Vector{MyType})`.
- **Don't** commit type piracy: adding methods to functions you don't own on types you don't own.
- **Don't** use the pipe operator `|>` for chaining. Assign intermediates to well-named variables.
- **Don't** use `@assert` for input validation or any check that must run in optimized builds. Use `throw(ArgumentError(...))`, `throw(DomainError(...))`, etc.
- **Don't** define a non-top-level named function. Use an anonymous function (`f = x -> ...`) for local helpers.

## 12. Control Flow Details

- **Use short-circuit `&&` / `||` for guard clauses and one-line conditional actions** — this is idiomatic Julia, not a trick:
  ```julia
  isempty(xs) && return nothing
  x === nothing && throw(ArgumentError("x is required"))
  verbose && @info "starting"
  ```
  Use a full `if` block when the action is multi-line or the condition is complex; don't force unreadable logic into `&&` chains.
- **Use comparison chaining** where it reads naturally: `0 < x < 1`, `lo <= i <= hi`.
- **Use `in` / `∈` for membership** (`x in (1, 2, 3)`, `c in "aeiou"`), and `∉` for non-membership — not a chain of `==`/`||`.
- **Ternary `cond ? a : b`** is fine on a single line only. Never chain ternaries; never wrap a ternary across multiple lines. Use `if/elseif/else` instead.
- **Use `if … elseif … else … end`** for multi-way branching needing more than two branches.
- **For empty `NamedTuple`** write `NamedTuple()`, not `(;)`.
- **For one-element `NamedTuple`** include the trailing comma: `(x=1,)`.
- **For splatting kwargs** use the leading `;`: `(; kwargs...)`.

## 13. Collections, Tuples, and Arrays — Multi-line Layout

- **Single-line collections:** no trailing comma. `arr = [1, 2, 3]`.
- **Multi-line collections:** opening bracket on the same line as `=`; closing bracket aligned with the start of the assignment; **trailing comma after the last element**:
  ```julia
  arr = [
      1,
      2,
      3,
  ]
  ```
- **Nested multi-line collections:** consistent indentation for inner and outer brackets.
- **Multi-line strings (triple-quoted):** the opening `"""` goes on the same line as the assignment; indent the body and closing `"""` consistently.

## 14. Iteration, Comprehensions, and the Base Function Vocabulary

- **Always use `for x in xs`.** Never `for x = xs` or `for x ∈ xs`. Applies to comprehensions too.
- **Use** `eachindex(A)`, `axes(A, d)`, `pairs(A)`, `enumerate(A)`, `zip(a, b)` rather than `1:length(A)` whenever possible.
- **Use** `@views` to avoid copies inside loop bodies on slices.

### Prefer the Base higher-order vocabulary over manual loops
Reach for these before writing an accumulation loop — they are clearer, type-stable, and often faster:
- **Transform/select:** `map(f, xs)`, `filter(pred, xs)`, comprehensions.
- **Reduce:** `reduce(op, xs)`, `foldl`/`foldr`, `mapreduce(f, op, xs)`, `sum(f, xs)`, `prod(f, xs)` (the function-arg forms fuse the map into the reduction — `sum(abs2, xs)`, not `sum(abs2.(xs))`).
- **Search/test:** `findfirst`, `findlast`, `findall`, `any(pred, xs)`, `all(pred, xs)`, `count(pred, xs)`.
- **Aggregate:** `extrema(xs)` (min and max in one pass), `minimum(f, xs)`, `maximum(f, xs)`.
- **Idiomatic predicates:** `isempty(x)` (never `length(x) == 0`), `!isempty(x)`, `isone`/`iszero`, `in`.

### Comprehension forms
- **Multidimensional:** `[f(i, j) for i in 1:n, j in 1:m]` builds a matrix directly.
- **Filtered:** `[x for x in xs if pred(x)]`.
- **Generator (no brackets)** when consumed once by a reduction (see §10): `sum(x^2 for x in xs)`.

### Iterators (lazy composition)
- **Use the `Iterators` module** for lazy, allocation-free composition: `Iterators.product`, `Iterators.flatten`, `Iterators.partition`, `Iterators.take`, `Iterators.drop`, `Iterators.zip`. Prefer these over materializing intermediate arrays.

### `Dict` access idioms
- **Use `get(d, k, default)`** for a read with fallback, and **`get!(d, k, default)`** to insert-and-return a default on miss. Don't write `haskey(d, k) ? d[k] : default`.
- **Iterate as pairs:** `for (k, v) in d`. Use `keys(d)`, `values(d)`, `pairs(d)`.
- **Use `get!(d, k) do … end`** when the default is expensive to compute (lazily evaluated only on miss).

### Building collections
- **Prefer comprehensions / `map` / generators over `push!` loops** to build collections; `sizehint!` when a `push!` loop is unavoidable (see §10, "Building collections").

## 15. Equality, Hashing, and Comparison

- **Use `===`** to test identity/egality (same object, or same immutable bits). **Use `==`** for value equality. **Use `isequal`** for the hashing / `Dict`-key notion of equality (treats `NaN` as equal to itself, distinguishes `-0.0` from `0.0`).
- **If you define `==` for a custom type, you MUST also define a consistent `hash`,** or the type will misbehave as a `Dict` key or `Set` element. Equal values must hash equal.
  ```julia
  struct Point
      x::Int
      y::Int
  end

  Base.:(==)(a::Point, b::Point) = a.x == b.x && a.y == b.y
  Base.hash(p::Point, h::UInt) = hash(p.y, hash(p.x, hash(:Point, h)))
  ```
- **Never test floating-point results with `==`.** Use `isapprox` / `≈` (with an explicit tolerance where it matters), in both code and tests.
- **Do not compare types with `==`** for dispatch logic; use `<:` and `isa` (see §7).

## 16. Representing Absence: `nothing`, `missing`, `Union{T,Nothing}`

- **Use `nothing`** (type `Nothing`) for "no value / not applicable" in ordinary control flow and optional returns. Test with `isnothing(x)` or `x === nothing`, **never** `x == nothing`.
- **Use `missing`** (type `Missing`) only for statistical missing data; it propagates through operations (`1 + missing === missing`) and is for data, not control flow. Use `coalesce` to supply defaults.
- **Type a possibly-absent value as `Union{T,Nothing}`** (a "small union", which Julia optimizes well), not as an untyped or `Any` field.
- **Prefer `something(x, default)`** to unwrap-with-fallback, and `@something` for short-circuiting.
- **A function that sometimes returns a value and sometimes nothing** should return `Union{T,Nothing}` and document it — do not return `T` in one branch and a sentinel like `-1` or `""` in another.

## 17. Strings

- **Julia `String`s are immutable and UTF-8 encoded; indexing is by byte, not character.** Do not assume `s[i]` is valid for every integer `i`. Iterate with `for c in s`, or use `eachindex(s)`, `nextind`, `prevind` for index arithmetic.
- **Build strings with an `IOBuffer` / `sprint`, or `join` / `string`,** not repeated `*` concatenation or interpolation inside a loop (each `*` allocates a new string):
  ```julia
  s = join(parts, ", ")            # good

  io = IOBuffer()                  # good for incremental building
  for x in xs
      print(io, x, ";")
  end
  s = String(take!(io))
  ```
- **For I/O, pass multiple arguments to `print`/`println`** rather than interpolating: `println(io, a, " ", b)` (see §10).
- **Use `Symbol`s (`:name`)** — not strings — for identifiers/keys compared by identity (field names, option tags). Symbols are interned and compared in O(1).

## 18. Documentation (docstrings)

- **Every exported function, type, macro, and module** must have a docstring. Internal functions should have docstrings when their behavior is non-trivial.
- **Docstrings are Markdown**, attached immediately above the definition with `"""…"""`.
- **First line is the signature**, indented 4 spaces (use `[x]` for optional positional args).
- **Second paragraph is a one-sentence summary** of what the function does.
- **Wrap docstring lines at 92 characters.**
- **Use these sections, in this order, when applicable:** `# Arguments`, `# Keywords`, `# Returns`, `# Throws`, `# Examples`. (Scientific projects following JuliaReach may use `### Input` / `### Output` / `### Notes` / `### Algorithm` / `### Examples` — pick one style per project and be consistent.)
- **Use** `jldoctest` blocks for runnable examples when rendered by Documenter.jl.
- **For methods that share a docstring,** attach one docstring to the function listing the multiple signatures.

Template:
```julia
"""
    mysearch(array::MyArray{T}, val::T; verbose=true) where {T} -> Int

Search `array` for `val`.

# Arguments
- `array::MyArray{T}`: the array to search.
- `val::T`: the value to search for.

# Keywords
- `verbose::Bool=true`: print progress details.

# Returns
- `Int`: the index where `val` is located.

# Throws
- `NotFoundError`: if `val` isn't found.
"""
function mysearch(array::MyArray{T}, val::T; verbose=true) where {T}
    ...
end
```

## 19. Comments

> The *philosophy* of commenting is in §0 (comment why not what; no narration; no scaffolding). This section covers mechanics.

- **Do** start comments with `# ` (hash + single space). Inline comments must be separated from the code by at least two spaces.
- **Do** keep comments up to date. Stale comments are worse than no comments.
- **Do** use `# TODO:` for to-dos and `# XXX:` for broken code that needs fixing — only in working/personal branches, never in delivered code as a substitute for implementation.
- **Do** quote code identifiers in comments with backticks: `` `variable_name` ``.
- **Do** capitalize the first word of a sentence and end complete sentences with periods; short fragments may omit the period.
- **Section comments:** in a genuinely long file, a sparse `# #### Section Name` style header is acceptable to separate major regions. Use them rarely. **Never** create banner walls, boxed ASCII art, or rows of `=`/`*`/`-`.

## 20. Custom Types: Accessors, `show`, and Standard Interfaces

- **Treat fields as private.** Provide accessor functions (`real(z)`, `imag(z)`) instead of having users reach into `z.re`, `z.im`.
- **Document the interface** (which functions a user can rely on); leave the rest as implementation detail. Document non-exported but stable API entries explicitly.
- **Define `Base.show` for your own types** when the default display is unhelpful. Define two-argument `show(io, x)` for a compact, ideally parseable form, and three-argument `show(io, ::MIME"text/plain", x)` for rich REPL display. Respect `get(io, :compact, false)`.
  ```julia
  Base.show(io::IO, p::Point) = print(io, "Point(", p.x, ", ", p.y, ")")
  ```
  Do **not** overload `show` on Base types like `Vector{MyType}` (see §11) — only on your own types.
- **If your type is a collection or iterable, implement the standard interface** so it works with `for`, comprehensions, and generic functions:
  - Iteration: `Base.iterate`, plus `Base.length` and `Base.eltype` where meaningful.
  - Array-like: implement the `AbstractArray` interface (`size`, `getindex`, `setindex!`, `IndexStyle`) rather than inventing ad-hoc accessors.
- **Define `Base.copy`** for mutable types users will copy; define `Base.similar` for array-like types.

## 21. Testing

- **Do** use the stdlib `Test` module.
- **Do** have exactly one root `@testset` in `test/runtests.jl`, including the sub-test files:
  ```julia
  using Test
  using MyPackage

  @testset "MyPackage" begin
      include("arithmetic.jl")
      include("utils.jl")
  end
  ```
- **Do** mirror `src/` in `test/` (one test file per source file when feasible) and wrap each file's contents in a nested `@testset "..." begin ... end`.
- **Do** use `@test_throws ExceptionType expr` to assert that invalid input raises the right exception type.
- **Do** use `@inferred f(args...)` to assert type stability — it errors if the inferred return type is not concrete. Add `@inferred` tests for performance-critical functions.
- **Do** use `@test_broken` for known-failing tests you intend to fix, rather than commenting them out or deleting them.
- **For float results,** test with `@test x ≈ y` (`isapprox`), not `==`. For exact integer results, `@test x == 0` (not `0.0`).
- **Do** parametrize repetitive tests with a loop inside the testset:
  ```julia
  @testset "abs($x)" for x in (-1, 0, 1)
      @test abs(x) >= 0
  end
  ```
- **Do** add tests for every exported function and for non-trivial internal helpers.
- **Don't** use `@assert` to test anything. Use `@test`.

## 22. Errors and Exceptions

- **Do** throw the most specific exception type: `ArgumentError`, `DomainError`, `BoundsError`, `KeyError`, or custom `<: Exception` subtypes for domain errors.
- **Error message style:** start with a lowercase word, no trailing period (matches Base).
- **Do** validate inputs at the boundary and let internal helpers assume validity.
- **Don't** catch broad exceptions silently. If you catch, either handle meaningfully or rethrow.

## 23. Logging, Randomness, and Reproducibility

### Logging
- **Use the `Logging` stdlib macros for diagnostics, not `println`:** `@debug`, `@info`, `@warn`, `@error`. They carry severity, can be filtered/redirected, and are suppressible. `println` is for actual program *output* a user asked for, not status messages.
- **Attach structured data as keyword-style fields:** `@info "converged" iterations=k residual=r`.
- **Use `@debug` for verbose internals** (off by default) instead of a `verbose` flag guarding `println`.

### Randomness and reproducibility
- **Thread an `AbstractRNG` through any function that uses randomness**, with a default:
  ```julia
  simulate(rng::AbstractRNG, n) = ...
  simulate(n) = simulate(Random.default_rng(), n)
  ```
  Then callers can pass a seeded RNG for reproducibility. Never call the global `rand()` deep inside library code.
- **Seed explicitly in tests and reproducible scripts** with `Random.seed!(seed)` (or a local `Xoshiro(seed)`), never rely on implicit global state.

## 24. Concurrency, Threading, and BLAS

- **Use `Threads.@threads for`** for simple data-parallel loops; `Threads.@spawn` + `@sync` for fork-join task parallelism. For distributed work, prefer `Threads.@spawn ... remotecall_fetch(...)` inside a `@sync` over `@spawnat ... fetch(...)` (single round trip vs two).
- **Avoid data races:** never let multiple threads write to the same variable or overlapping array indices without synchronization. Prefer one of: per-thread partial results combined afterward (a reduction), `Threads.Atomic` for simple counters, or a `ReentrantLock` around genuinely shared mutable state.
- **Thread-local accumulation pattern:** give each thread its own accumulator (e.g. indexed by `Threads.threadid()` or a per-chunk local), then reduce across them — do not `+=` into a shared scalar from multiple threads.
- When using Julia threads for code that also calls BLAS, **set `OPENBLAS_NUM_THREADS=1`** (or `BLAS.set_num_threads(1)`) to avoid oversubscribing cores. Benchmark to tune.

## 25. Quick "Always / Never" Checklist

**Always:**
- Do only what's asked; match existing code; produce minimal diffs.
- Comment _why_, not _what_. Verify code runs before claiming done.
- 4-space indentation. UTF-8. Trailing newline at EOF.
- `using` over `import`; one package per line; alphabetical.
- `UpperCamelCase` types/modules; `snake_case` functions/vars; `SCREAMING_SNAKE_CASE` consts.
- `!` suffix on mutating functions; mutated arg first.
- Explicit `return` in long-form functions; omit in short form.
- Spaces around binary operators; no spaces around `=` in kwargs/NamedTuples.
- `for x in xs`. `0.1`, not `.1`.
- Concrete parametric types in struct fields.
- Comprehension / `map` / generator over `push!` loops; `sizehint!` when you must push.
- `@enum` for fixed value sets.
- Preallocate; use `@views`; broadcast with `.`.
- Pair `hash` with any custom `==`; use `≈` for float comparisons.
- `isnothing(x)`, not `x == nothing`.
- Build strings with `join` / `IOBuffer`, not `*` in a loop.
- Define `show` for your own types; implement standard interfaces for your collections.
- Doc every exported name. Run `@code_warntype` / `@inferred` on hot functions.
- Use short-circuit `&&`/`||` for guard clauses; comparison chaining; `in` for membership.
- Return tuples and destructure (`lo, hi = f()`, `(; x, y) = nt`); use `first`/`last`/`only`.
- Reach for the Base vocabulary: `sum(f, xs)`, `count(pred, xs)`, `any`/`all`, `findfirst`, `mapreduce`, `extrema`; `get`/`get!` for Dicts; `zip`/`Iterators.*`.
- Use the `Logging` macros (`@info`/`@warn`/`@debug`) for diagnostics, not `println`.
- Design hot-path structs to be `isbits` (immutable, concrete fields); `Tuple`/`NamedTuple` for small fixed data.
- Use in-place LinearAlgebra (`mul!`, `ldiv!`, `copyto!`) and target zero allocations in hot loops.
- Write index-agnostic generic code: `eachindex`, `axes`, `firstindex`/`lastindex`, `similar`, `promote_type`.
- `round(Int, x)` / `parse(T, s)`; watch silent `Int` overflow; use `hypot`/`log1p`/`muladd`/`evalpoly`.
- Thread an `AbstractRNG`; `Random.seed!` in tests. Build paths with `joinpath(@__DIR__, …)`.

**Never:**
- Add unrequested features, abstraction, or config. Reformat unrelated code.
- Write narration comments, leftover debug prints, or commented-out code.
- Emit emoji, ASCII banners, or comment divider walls.
- Reinvent stdlib; invent APIs you haven't verified.
- Use a bare boolean positional argument (the boolean trap).
- Tabs. Trailing whitespace. Aligned `=` columns.
- `importall`. Unqualified `import Module: f` to extend `f`.
- Type piracy. Abstract field types (`::AbstractFloat`, `::Function`, `::Array`).
- Mutate a local variable's type mid-function.
- `1:length(A)` for indexing. `for i = 1:n`. The `|>` operator for chaining.
- `@assert` for input validation. Bare `return` (write `return nothing`).
- `x == nothing`; `==` on float results; `==` without a matching `hash`.
- The `global` keyword to mutate state in hot code.
- Wrap a named function in `x -> f(x)` to pass it.
- Unprompted `main()` / entrypoint blocks / example dumps.
- `println` for status/diagnostics (use logging); the global `rand()` deep in library code.
- Assume 1-based indexing or a concrete `eltype` in generic code.
- Abstract or mutable fields in structs meant to live in hot `Vector`s (breaks `isbits`).
- `Int(round(x))` (use `round(Int, x)`); ignore silent `Int` overflow on large inputs.
- `length(x) == 0` (use `isempty`); `haskey(d,k) ? d[k] : default` (use `get`).
- Concurrent writes to shared state without a reduction, `Atomic`, or lock.
- Bare relative file paths (use `joinpath(@__DIR__, …)`).
