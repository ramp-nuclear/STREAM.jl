# JULIA.md

How Julia is written in this repository. `CLAUDE.md` covers the project's layout,
docstrings and MTK usage.

## Idiom

- **Short code.** Fewer lines and fewer intermediate names. Reach for broadcasting and vector
  operations (`f.(x)`, `x .~ y`, `sum(f, xs)`) first; keep a comprehension where it is
  clearer (nested generation, filtering) and an index loop where neither fits.
- **Use `Base` and the stdlib** (`maximum`, `extrema`, `findfirst`, `count`, `mapreduce`,
  `only`, `get`) rather than hand-rolling them.
- No debug `println`/`@show` left behind, and no `abspath(PROGRAM_FILE) == @__FILE__` blocks.

## Layout and imports

- Imports go at the top of `src/STREAM.jl` or of the submodule block that needs them, never
  in an `include`d file. `using` over `import`; one package per line.
- To extend a function, qualify it: `Base.show(io::IO, x::MyType) = ...`, never
  `import Base: show`.
- Write qualified macros as `Module.@macro`, not `@Module.macro`.
- Build file paths with `joinpath(@__DIR__, ...)` or `pkgdir(STREAM)`, never bare relative
  strings.

## Naming

- `UpperCamelCase` for modules and types, `snake_case` or squashed lowercase for functions
  and variables, `SCREAMING_SNAKE_CASE` for constants. Abstract types start with `Abstract`.
- Mutating functions end in `!`, with the mutated argument first.
- Private names start with `_` and are not exported.
- Physics symbols keep their conventional letter (`ρ`, `cₚ`, `ṁ`, `Re`).

## Formatting

Nothing enforces formatting yet; `.JuliaFormatter.toml` (Blue style, 92 columns) is the
target. Until it runs:

- 4-space indents, no tabs. Lines up to 92 characters, soft limit.
- One space after commas and around binary operators; none around `^`, `:` or `//`, and
  none inside brackets.
- No spaces around `=` in keyword arguments and `NamedTuple`s: `f(x; y=3)`, `(a=1, b=2)`.
- Separate positional from keyword arguments with `;` at call sites.
- Do not align `=` across lines. No two consecutive blank lines.
- Floats carry both zeros: `0.1`, `2.0`.
- `for x in xs`, never `for x = xs` or `for x ∈ xs`.
- A signature too long for one line puts every argument on its own line, indented once, with
  a trailing comma and `)` aligned with `function`.
- Multi-line collections end with a trailing comma; single-line ones do not.
- Comments start with `# `; an inline comment sits two spaces after the code.

## Functions and types

- Short form `f(x) = ...` only when it fits on one line.
- No `return nothing`: a function called for its effect just ends.
- Annotate arguments loosely (`AbstractVector`, `Real`) and only as tightly as dispatch needs.
  Omit names of unused arguments: `f(::Number, y) = y`.
- Struct fields are concrete or parametric, never abstract. Use a type parameter for a
  function-valued field rather than `::Function`.
- Prefer small methods dispatching on type to `isa` branches. No type piracy.
- A flag is a keyword argument, an `@enum`, or a type to dispatch on, never a bare
  positional `Bool`.
- Keep functions type-stable: `zero(x)`, not `0`, as the other branch of a `Float64` result.
- Return several values as a tuple or `NamedTuple`, and destructure with `(; a, b) = nt`.
- Use `first`, `last` and `only` instead of `x[1]`, `x[end]` and an assumed single element.
- Pass `f` rather than `x -> f(x)`.
- No `|>` chains; name the intermediate values.
- Ternaries stay on one line and are never nested.
- Guard clauses with `&&`/`||`: `x < 0 && throw(DomainError(x))`.

## Numbers and comparisons

- `round(Int, x)`, not `Int(round(x))`.
- `isapprox`/`≈` for floats, never `==`. `isnothing(x)`, not `x == nothing`.
- `isempty(x)`, not `length(x) == 0`. `get(d, k, default)`, not `haskey(d, k) ? d[k] : ...`.
- `hypot`, `log1p`, `expm1` and `evalpoly` where they apply.

## Errors

- Throw the most specific exception: `ArgumentError`, `DomainError`, or a custom subtype.
- Messages start lowercase and have no trailing period.
- Never `@assert` for input validation. (`@assert` in a docs page, checking physics, is fine.)

## Tests

- Use the `Test` stdlib.
- `@test x ≈ y` for floats; `@test_throws` for invalid input; `@test_broken` for a known
  failure, rather than commenting it out.
- Parametrize repetition with `@testset "..." for x in xs`.
