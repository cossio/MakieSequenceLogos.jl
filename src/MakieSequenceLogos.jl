module MakieSequenceLogos

import Makie, FreeType, FreeTypeAbstraction, GeometryBasics

using Makie
using GeometryBasics: Point2f
using Colors: @colorant_str, Colorant
using FreeType
using FreeTypeAbstraction
using FreeType: FT_Load_Glyph, FT_LOAD_NO_SCALE, FT_LOAD_NO_BITMAP, FT_Outline_Funcs

include("glyphs.jl")
include("matrices.jl")
include("colors.jl")
include("render.jl")

export seqlogo, seqlogo!
export pfm, ppm, pwm, information_content
export DNA_ALPHABET, RNA_ALPHABET, PROTEIN_ALPHABET

end # module
