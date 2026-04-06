# Color scheme definitions for sequence logos

const DNA_CLASSIC = Dict{Char, Colorant}(
    'A' => colorant"#009e73",   # green
    'C' => colorant"#0072b2",   # blue
    'G' => colorant"#e69f00",   # orange
    'T' => colorant"#d55e00",   # red
    'U' => colorant"#d55e00",   # red (RNA)
)

const PROTEIN_CHEMISTRY = Dict{Char, Colorant}(
    # Hydrophobic (black)
    'A' => colorant"#000000", 'F' => colorant"#000000",
    'I' => colorant"#000000", 'L' => colorant"#000000",
    'M' => colorant"#000000", 'P' => colorant"#000000",
    'V' => colorant"#000000", 'W' => colorant"#000000",
    # Polar (green)
    'C' => colorant"#009e73", 'G' => colorant"#009e73",
    'S' => colorant"#009e73", 'T' => colorant"#009e73",
    'Y' => colorant"#009e73", 'N' => colorant"#009e73",
    'Q' => colorant"#009e73",
    # Positive charge (blue)
    'H' => colorant"#0072b2", 'K' => colorant"#0072b2",
    'R' => colorant"#0072b2",
    # Negative charge (red)
    'D' => colorant"#d55e00", 'E' => colorant"#d55e00",
)

const COLOR_SCHEMES = Dict{Symbol, Dict{Char, Colorant}}(
    :classic     => DNA_CLASSIC,
    :dna         => DNA_CLASSIC,
    :rna         => DNA_CLASSIC,
    :protein     => PROTEIN_CHEMISTRY,
    :chemistry   => PROTEIN_CHEMISTRY,
)

"""
    get_color_scheme(name) -> Dict{Char, Colorant}

Return one of the built-in color schemes for sequence logos.
"""
function get_color_scheme(name::Symbol)
    haskey(COLOR_SCHEMES, name) && return COLOR_SCHEMES[name]
    error("Unknown color scheme: $name. Available: $(join(keys(COLOR_SCHEMES), ", "))")
end

"""
    get_color(char, scheme) -> Colorant

Look up the display color for `char`, falling back to gray when the character
is not present in `scheme`.
"""
get_color(char::Char, scheme::Dict{Char, <:Colorant}) = get(scheme, char, colorant"#808080")
