# The scripts, stylesheets and fonts the built pages use, kept locally so that the site loads
# nothing from the internet when it is built or viewed. Download them once, with internet
# access:
#   julia docs/vendor.jl
# They go to the directory STREAM_DOCS_VENDOR names, docs/vendor by default, laid out by host
# and path as on the CDN they come from. make.jl includes this file: it stops before building
# if a file is missing, and after the build copies them into it and points every page at them.
# A module, so that make.jl's Main, where DocumenterCodeBlocks resolves names, stays clean.
module Vendor

using Downloads

const VENDOR = abspath(get(ENV, "STREAM_DOCS_VENDOR", joinpath(@__DIR__, "vendor")))

const CDNJS = "https://cdnjs.cloudflare.com/ajax/libs/"

# Mermaid 11.6.0, pinned: newer releases fail next to the RequireJS Documenter loads.
const MERMAID = "https://cdn.jsdelivr.net/npm/mermaid@11.6.0/dist/mermaid.min.js"

# What Documenter's theme loads, at the versions this Documenter release names, and Mermaid.
# The fonts a stylesheet refers to come along with it.
const FILES = [
    CDNJS * "KaTeX/0.16.8/katex.min.css",
    CDNJS * "KaTeX/0.16.8/katex.min.js",
    CDNJS * "KaTeX/0.16.8/contrib/auto-render.min.js",
    CDNJS * "font-awesome/6.4.2/css/fontawesome.min.css",
    CDNJS * "font-awesome/6.4.2/css/solid.min.css",
    CDNJS * "font-awesome/6.4.2/css/brands.min.css",
    CDNJS * "juliamono/0.63.2/juliamono.min.css",
    CDNJS * "lato-font/3.0.0/css/lato-font.min.css",
    CDNJS * "require.js/2.3.6/require.min.js",
    CDNJS * "jquery/3.7.0/jquery.min.js",
    CDNJS * "jqueryui/1.13.2/jquery-ui.min.js",
    CDNJS * "headroom/0.12.0/headroom.min.js",
    CDNJS * "headroom/0.12.0/jQuery.headroom.min.js",
    CDNJS * "highlight.js/11.8.0/highlight.min.js",
    CDNJS * "highlight.js/11.8.0/languages/julia.min.js",
    CDNJS * "highlight.js/11.8.0/languages/julia-repl.min.js",
    CDNJS * "minisearch/6.2.0/umd/index.min.js",
    MERMAID,
]

# Hosts a built page must not load anything from once the files are in place.
const REMOTE_HOSTS = ["cdnjs.cloudflare.com", "cdn.jsdelivr.net", "unpkg.com",
                      "fonts.googleapis.com", "fonts.gstatic.com"]

"""
    local_path(url, root=VENDOR) -> String

Where the file at `url` is kept under `root`: its host, then its path.
"""
local_path(url, root=VENDOR) = joinpath(root, split(replace(url, r"^https?://" => ""), '/')...)

"""
    resolve(base, ref) -> String

The absolute URL of `ref`, a reference made by the file at `base`.
"""
function resolve(base, ref)
    occursin(r"^https?://", ref) && return ref
    host, path = match(r"^(https?://[^/]+)(/.*)$", base).captures
    parts = String[]
    for p in split(path[1:findlast('/', path)] * ref, '/')
        p in ("", ".") && continue
        p == ".." ? pop!(parts) : push!(parts, p)
    end
    return host * "/" * join(parts, '/')
end

"""
    css_references(css, base) -> Vector{String}

The files the stylesheet `css`, found at `base`, loads with `url(...)`, as absolute URLs.

Of the fonts, only the WOFF2 ones: a stylesheet lists older formats after them as fallbacks,
which every browser that runs these pages skips, and the CDN does not always have them.
"""
function css_references(css, base)
    refs = String[]
    for m in eachmatch(r"url\(\s*['\"]?([^'\")]+)['\"]?\s*\)", css)
        ref = first(split(m.captures[1], ['?', '#']))
        startswith(ref, "data:") && continue
        occursin(r"\.(woff|ttf|otf|eot|svg)$", ref) && continue
        push!(refs, resolve(base, ref))
    end
    return unique(refs)
end

"""
    vendor_files(root=VENDOR; download=false) -> (; found, missing)

Every file the pages need, following the stylesheets to the fonts they load. With
`download=true`, a file not yet under `root` is downloaded; otherwise it is listed as missing.
"""
function vendor_files(root=VENDOR; download=false)
    queue, found, missing = copy(FILES), String[], String[]
    while !isempty(queue)
        url = popfirst!(queue)
        (url in found || url in missing) && continue
        path = local_path(url, root)
        if !isfile(path) && download
            mkpath(dirname(path))
            mv(Downloads.download(url), path)
        end
        isfile(path) || (push!(missing, url); continue)
        push!(found, url)
        endswith(url, ".css") && append!(queue, css_references(read(path, String), url))
    end
    return (; found, missing)
end

"""
    check_vendor(root=VENDOR)

Throw if a file the pages need is not under `root`, saying how to get it.
"""
function check_vendor(root=VENDOR)
    missing = vendor_files(root).missing
    isempty(missing) && return nothing
    error("The pages load their scripts and fonts from $root, which lacks ",
          join(missing, ", "), ". Download them once with `julia docs/vendor.jl`, or set ",
          "STREAM_DOCS_VENDOR to a directory that has them.")
end

"""
    replace_once(text, pair, what) -> String

`text` with the one occurrence of `first(pair)` replaced. Throws when there is not exactly one,
which means Documenter has changed how it loads `what`.
"""
function replace_once(text, pair, what)
    n = count(first(pair), text)
    n == 1 || error("Documenter's assets/documenter.js has $n places that load $what, not one. ",
                    "Update docs/vendor.jl for this Documenter release.")
    return replace(text, pair)
end

"""
    install_vendor(build, root=VENDOR)

Copy the files into `build/assets/vendor` and point every page at them instead of the CDNs:
the stylesheets and RequireJS in each page's head, the libraries RequireJS loads, the search
worker's minisearch, and Mermaid on the pages that have a diagram. Throws if anything in the
build still loads from a CDN afterwards.
"""
function install_vendor(build, root=VENDOR)
    check_vendor(root)
    assets = joinpath(build, "assets")
    target = joinpath(assets, "vendor")
    cp(root, target; force=true)

    # RequireJS resolves its paths against assets/, where documenter.js is.
    js = joinpath(assets, "documenter.js")
    text = read(js, String)
    m = match(r"importScripts\(\s*\"(https://[^\"]+)\"", text)
    m === nothing && error("Documenter's assets/documenter.js no longer loads minisearch with ",
                           "importScripts. Update docs/vendor.jl for this Documenter release.")
    search = m.captures[1]
    # The search worker is made from a Blob, which has no address of its own, so the page
    # works out minisearch's absolute address and writes it into the worker before starting it.
    text = replace_once(text, "\"$search\"" => "\"__STREAM_MINISEARCH__\"", "minisearch")
    text = replace_once(text, "worker_function.toString()" =>
        "worker_function.toString().replace(\"__STREAM_MINISEARCH__\", new URL(" *
        "documenterBaseURL + \"/assets/vendor/" * replace(search, r"^https://" => "") *
        "\", window.location.href).href)", "the search worker")
    for host in REMOTE_HOSTS
        text = replace(text, "'https://$host/" => "'vendor/$host/")
    end
    write(js, text)

    mermaid = "/vendor/" * replace(MERMAID, r"^https://" => "")
    for (dir, _, files) in walkdir(build), file in files
        endswith(file, ".html") || continue
        startswith(dir, target) && continue
        page = joinpath(dir, file)
        up = replace(relpath(assets, dir), '\\' => '/')
        html = read(page, String)
        for host in REMOTE_HOSTS
            html = replace(html, "https://$host/" => "$up/vendor/$host/")
        end
        # Mermaid goes in ahead of RequireJS, which would otherwise take the AMD modules
        # bundled inside it for its own.
        if occursin("class=\"mermaid\"", html)
            tag = "<script src=\"$up$mermaid\"></script>"
            html = replace(html, r"<script[^>]*data-main=" => s -> tag * s; count=1)
        end
        write(page, html)
    end

    remote = String[]
    for (dir, _, files) in walkdir(build), file in files
        startswith(dir, target) && continue
        any(ext -> endswith(file, ext), (".html", ".js", ".css")) || continue
        text = read(joinpath(dir, file), String)
        for host in REMOTE_HOSTS
            occursin("//$host", text) && push!(remote, "$(relpath(joinpath(dir, file), build)): $host")
        end
    end
    isempty(remote) || error("The build still loads from a CDN:\n  ", join(remote, "\n  "),
                             "\nAdd the file to docs/vendor.jl.")
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    files = vendor_files(VENDOR; download=true)
    println(length(files.found), " files in ", VENDOR)
end

end
