```@meta
EditURL = "rfam.jl"
```

# MakieSequenceLogos examples with RFAM

````@example rfam
import Makie, CairoMakie, MakieSequenceLogos
using Statistics: mean
using LogExpFunctions: xlogx
````

Sample RNA alignment inspired by an RFAM family

````@example rfam
seqs = [
    "GGAAAUCCU",
    "GGAAAUCCU",
    "GGAAAUCCU",
    "GGAAA-CCU",
    "GGAAGUCCU",
    "GGAAAUUCU",
]
nothing #hide
````

RNA nucleotides

````@example rfam
NTs = "ACGU-";
nothing #hide
````

One-hot representation

````@example rfam
function onehot(s::String)
    return reshape(collect(s), 1, length(s)) .== collect(NTs)
end
X = reshape(reduce(hcat, onehot.(seqs)), 5, :, length(seqs));
nothing #hide
````

Sequence logo

````@example rfam
xlog2x(x) = xlogx(x) / log(oftype(x,2))
p = dropdims(mean(X; dims=3); dims=3)
H = sum(-xlog2x.(p); dims=1)
````

Plot!

````@example rfam
fig = Makie.Figure()
ax = Makie.Axis(fig[1,1]; width=800, height=150, xlabel="position", ylabel="conservation (bits)")
MakieSequenceLogos.seqlogo!(ax, p .* (log2(5) .- H), collect(NTs); color_scheme=:classic)
Makie.resize_to_layout!(fig)
fig
````

---

*This page was generated using [Literate.jl](https://github.com/fredrikekre/Literate.jl).*
