#=
# MakieSequenceLogos examples with RFAM
=#

import GitHub, Makie, CairoMakie, MakieSequenceLogos
using Downloads: download
using Statistics: mean
using LogExpFunctions: xlogx

# Fetch RNA family alignment RF00162 from RFAM (pre-stored as a Github Gist)

data = GitHub.gist("b63e87024fac287a1800b1555276a04b")
url = data.files["RF00162-trimmed.afa"]["raw_url"]
path = download(url; timeout = Inf)
nothing #hide

# Parse lines

seqs = String[]
for line in eachline(path)
    if startswith(line, '>')
        continue
    else
        push!(seqs, line)
    end
end

# RNA nucleotides

NTs = "ACGU-";

# One-hot representation

function onehot(s::String)
    return reshape(collect(s), 1, length(s)) .== collect(NTs)
end
X = reshape(reduce(hcat, onehot.(seqs)), 5, :, length(seqs));

# Sequence logo

xlog2x(x) = xlogx(x) / log(oftype(x,2))
p = dropdims(mean(X; dims=3); dims=3)
H = sum(-xlog2x.(p); dims=1)

# Plot!

fig = Makie.Figure()
ax = Makie.Axis(fig[1,1]; width=500, height=200, xlabel="position", ylabel="conservation (bits)")
MakieSequenceLogos.seqlogo!(ax, p .* (log2(5) .- H), collect(NTs); color_scheme=:classic)
Makie.resize_to_layout!(fig)
fig
