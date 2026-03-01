import Makie, CairoMakie, MakieSequenceLogos

plots_dir = mktempdir()
@info "Saving demo plots to $plots_dir"

# --- Example 1: DNA sequence logo from aligned sequences ---

sequences = [
    "AGGCTGAT",
    "AGGCTGAT",
    "AGTCTGAT",
    "AGGCAGAT",
    "AGGCTGAT",
    "CGGCTGAT",
    "AGGCTGAT",
    "AGGCTGTT",
    "AGGCTGAT",
    "AGGCTGAT",
]

fig = MakieSequenceLogos.seqlogo(sequences; alphabet_name = :dna, matrix_type = :information)
save(joinpath(plots_dir, "dna_logo.png"), fig; px_per_unit = 2)
@info "Saved $(joinpath(plots_dir, "dna_logo.png"))"

# --- Example 2: From a custom matrix ---

alphabet = ['A', 'C', 'G', 'T']
# Matrix is q × L (rows = alphabet letters, columns = positions)
mat = [
    1.5  0.1  0.3  0.0  0.5;
    0.2  0.1  1.2  0.0  0.5;
    0.1  1.8  0.3  0.0  0.5;
    0.2  0.0  0.2  2.0  0.5;
]

fig2 = MakieSequenceLogos.seqlogo(mat, alphabet; color_scheme = :classic)
save(joinpath(plots_dir, "custom_logo.png"), fig2; px_per_unit = 2)
@info "Saved $(joinpath(plots_dir, "custom_logo.png"))"
