# Build the documentation:
#   julia --project=docs docs/make.jl            # full build, runs every example
#   DRAFT=1 julia --project=docs docs/make.jl    # prose only, skips running code
#   PREVIEW=1 julia --project=docs docs/make.jl  # runs the code, but reports broken links as
#                                                # warnings, for previewing unfinished pages
# A draft build also reports broken links as warnings.
# Preview the result with `python3 -m http.server -d docs/build 8000`. This only builds:
# docs/deploy.jl publishes a finished build, and only CI runs it.
#
# The pages load their scripts, stylesheets and fonts from the build itself, never from the
# internet. Download those once with `julia docs/vendor.jl`; STREAM_DOCS_VENDOR names where
# they are kept, docs/vendor by default.
using Documenter
using DocumenterCitations
using DocumenterCodeBlocks
using DocumenterMermaid
using Literate
using CairoMakie
using STREAM
# DocumenterCodeBlocks links names in code blocks by resolving them in Main, so bring in the
# submodules the pages import from. Channel is named explicitly: Base has one too.
using STREAM.Components, STREAM.Assemblies, STREAM.Thresholds, STREAM.Utilities
using STREAM.Components: Channel

include("vendor.jl")
Vendor.check_vendor()

const DRAFT = get(ENV, "DRAFT", "") == "1"
# Makie's settings are global, so they hold in every page's example module: plots are SVG.
CairoMakie.activate!(type="svg")

const PREVIEW = DRAFT || get(ENV, "PREVIEW", "") == "1"
const LITERATE = joinpath(@__DIR__, "literate")
const TUTORIALS = joinpath(@__DIR__, "src", "tutorials")

# Each tutorial is written once, as a script, and becomes a page, a script and a notebook.
# The script and notebook land next to the page, so the page links to them by file name.
tutorials = Any["Overview" => "tutorials/index.md"]
for file in sort(readdir(LITERATE))
    endswith(file, ".jl") || continue
    src = joinpath(LITERATE, file)
    Literate.markdown(src, TUTORIALS; documenter=true, credit=false)
    Literate.script(src, TUTORIALS; credit=false)
    Literate.notebook(src, TUTORIALS; execute=false, credit=false)
    push!(tutorials, joinpath("tutorials", replace(file, ".jl" => ".md")))
end

# DocumenterMermaid ends every page with a script that loads Mermaid from a CDN. Here it only
# starts Mermaid: install_vendor puts the local copy in the head of each page with a diagram,
# and a page without one has no Mermaid to start.
function Documenter.HTMLWriter.domify(::Documenter.HTMLWriter.DCtx, ::Documenter.Node,
                                      ::DocumenterMermaid.MermaidScriptBlock)
    Documenter.DOM.@tags script
    return script("""
    if (window.mermaid) { mermaid.initialize({ startOnLoad: true, theme: "neutral" }); }
    """)
end

DocMeta.setdocmeta!(STREAM, :DocTestSetup, :(using STREAM); recursive=true)

bib = CitationBibliography(joinpath(@__DIR__, "src", "refs.bib"); style=:authoryear)

reference = [
    "Overview" => "reference/index.md",
    "Top level" => "reference/stream.md",
    "Substances" => "reference/substances.md",
    "HTC" => "reference/htc.md",
    "Friction" => "reference/friction.md",
    "LocalLoss" => "reference/local_loss.md",
    "Thresholds" => "reference/thresholds.md",
    "Components" => "reference/components.md",
    "DecayHeat" => "reference/decay_heat.md",
    "Assemblies" => "reference/assemblies.md",
    "Solvers" => "reference/solvers.md",
    "Utilities" => "reference/utilities.md",
]

# A page listed here that does not exist yet is skipped, so the navigation can be written
# ahead of the pages.
exists(page) = isfile(joinpath(@__DIR__, "src", page))
keep(pages) = Any[p for p in pages if exists(last(p))]

howto = keep([
    "Overview" => "howto/index.md",
    "Bind a wall temperature or heat flux" => "howto/wall_boundary.md",
    "Choose heat transfer and friction models" => "howto/models.md",
    "Change the coolant" => "howto/coolant.md",
    "Wire components together" => "howto/wiring.md",
    "Build a fuel assembly" => "howto/fuel_assembly.md",
    "Model a clad plate or a fuel rod" => "howto/heat_structures.md",
    "Set up a tank for the steady solve" => "howto/tanks.md",
    "Model a break" => "howto/breaks.md",
    "Get a steady solve to converge" => "howto/steady_solve.md",
    "Trip a reactor or open a valve" => "howto/events.md",
    "Add decay heat to a transient" => "howto/decay_heat.md",
    "Compute safety margins" => "howto/margins.md",
    "Scan a design parameter" => "howto/design_knobs.md",
    "Drive an input from a function of time" => "howto/time_inputs.md",
    "Move a profile between meshes" => "howto/rebin.md",
])

limits = keep([
    "Overview" => "explanation/limits/overview.md",
    "Onset of nucleate boiling" => "explanation/limits/onb.md",
    "Onset of significant void" => "explanation/limits/osv.md",
    "Onset of flow instability" => "explanation/limits/ofi.md",
    "Critical heat flux" => "explanation/limits/chf.md",
    "Wall temperature limit" => "explanation/limits/twall.md",
    "Margins" => "explanation/limits/margins.md",
])

mtk = keep([
    "Overview" => "explanation/mtk/index.md",
    "A series RLC circuit" => "explanation/mtk/rlc.md",
    "Masses on springs" => "explanation/mtk/springs.md",
    "A planar pendulum" => "explanation/mtk/pendulum.md",
])

explanation = keep([
    "Overview" => "explanation/index.md",
    "How a model is built" => "explanation/modelling.md",
    "The coolant channel" => "explanation/channel.md",
    "Wall heat transfer" => "explanation/heat_transfer.md",
    "Heat exchangers and the heat sink" => "explanation/heat_exchanger.md",
    "Pressure drop" => "explanation/pressure_drop.md",
    "Heat conduction in fuel" => "explanation/conduction.md",
    "Point kinetics and feedback" => "explanation/point_kinetics.md",
    "Decay heat" => "explanation/decay_heat.md",
    "Loss of coolant" => "explanation/loca.md",
    "Events and control" => "explanation/events.md",
    "Relation to Python STREAM" => "explanation/python.md",
])
isempty(mtk) || insert!(explanation, 3, "ModelingToolkit in brief" => mtk)
isempty(limits) || push!(explanation, "Thermal-hydraulic limits" => limits)

pages = Any["Home" => "index.md"]
push!(pages, "Tutorials" => tutorials)
isempty(howto) || push!(pages, "How-to guides" => howto)
isempty(explanation) || push!(pages, "Explanation" => explanation)
push!(pages, "Reference" => reference, "Bibliography" => "bibliography.md")

makedocs(;
    sitename="STREAM.jl",
    modules=[STREAM],
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", nothing) == "true",
        canonical="https://ramp-nuclear.github.io/STREAM.jl",
        edit_link="main",
        size_threshold_warn=400 * 2^10,
        size_threshold=800 * 2^10,
        # The search index grows with every page; it is loaded once, so its size matters less.
        search_size_threshold_warn=1024 * 2^10,
    ),
    pages,
    plugins=[bib, CodeBlocks()],
    checkdocs=:exports,
    draft=DRAFT,
    warnonly=PREVIEW,
)

Vendor.install_vendor(joinpath(@__DIR__, "build"))
