# MakieSequenceLogos Julia package

[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://cossio.github.io/MakieSequenceLogos.jl/stable)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://cossio.github.io/MakieSequenceLogos.jl/dev)

A package to plot [sequence logos](https://en.wikipedia.org/wiki/Sequence_logo) in Julia using [Makie](https://docs.makie.org/stable/). See example [demo.jl](https://github.com/cossio/MakieSequenceLogos.jl/blob/main/repl/demo.jl), or see example in the docs.

This package is registered. Install with:

```julia
using Pkg
Pkg.add("MakieSequenceLogos")
```

## Related

In constrast to this package, which is a "native" Julia implementation based on Makie, the following packages require Python dependencies:

* https://github.com/cossio/Logomaker.jl - A thin Julia wrapper of the Logomaker Python package to plot sequence logos.
* https://github.com/cossio/SequenceLogos.jl - Implementation based on PyPlot.