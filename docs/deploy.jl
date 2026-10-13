# Publish a finished build, docs/build, to the gh-pages branch:
#   julia --project=docs docs/deploy.jl
# Only the deploy job in .github/workflows/docs.yml runs this, after the build job has made
# docs/build with docs/make.jl. Run locally, Documenter sees no CI and deploys nothing.
using Documenter

# main goes to dev/, a tag to its version, and a pull request from this repository to
# previews/PR<number>/.
deploydocs(; repo="github.com/ramp-nuclear/STREAM.jl", devbranch="main", push_preview=true)
