#!/usr/bin/env -S julia --startup-file=no

using Documenter
using DataToolkitBase
using Org

orgfiles = filter(f -> endswith(f, ".org"),
                  readdir(joinpath(@__DIR__, "src"), join=true))

for orgfile in orgfiles
    mdfile = replace(orgfile, r"\.org$" => ".md")
    read(orgfile, String) |>
        c -> Org.parse(OrgDoc, c) |>
        o -> sprint(markdown, o) |>
        s -> replace(s, r"\.org]" => ".md]") |>
        m -> write(mdfile, m)
end

makedocs(;
    modules=[DataToolkitBase],
    format=Documenter.HTML(),
    pages=[
        "Introduction" => "index.md",
        "Usage" => "usage.md",
        "Data.toml" => "datatoml.md",
        "REPL" => "repl.md",
        "Extensions" => Any[
            "Transformer backends" => "newtransformer.md",
            "Packages" => "packages.md",
            "Data Advice" => "advising.md",
        ],
        "Internals" => "libinternal.md",
        "Errors" => "errors.md",
    ],
    repo="https://github.com/tecosaur/DataToolkitBase.jl/blob/{commit}{path}#L{line}",
    sitename="DataToolkitBase.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkitBase.jl/graphs/contributors",
    warnonly = [:missing_docs],
)

deploydocs(;
    repo="github.com/tecosaur/DataToolkitBase.jl",
    devbranch = "main"
)
