# Makie rendering for sequence logos

"""
    seqlogo!(ax::Axis, matrix::AbstractMatrix, alphabet::AbstractVector{Char}; kwargs...)

Plot a sequence logo onto an existing Makie `Axis`.

`matrix` has size `(L, C)` where `L` is the number of positions and `C = length(alphabet)`.
Each entry encodes the height of the corresponding character at that position.

# Keyword arguments
- `color_scheme`: a `Symbol` (`:classic`, `:dna`, `:protein`, …) or `Dict{Char, <:Colorant}`.
- `font`: path to a `.ttf` / `.otf` file.  Default: NotoSans-Bold bundled with Makie.
- `sort_letters`: stack letters bottom-to-top by ascending height (default `true`).
- `ylabel`: y-axis label (default `"Information content (bits)"`).
"""
function seqlogo!(ax::Makie.Axis, matrix::AbstractMatrix, alphabet::AbstractVector{Char};
                   color_scheme::Union{Symbol, Dict{Char, <:Colorant}} = :classic,
                   font::String = _default_font_path(),
                   sort_letters::Bool = true,
                   ylabel::String = "Information content (bits)")

    mat = validate_matrix(matrix, alphabet)
    L, C = size(mat)
    colors = color_scheme isa Symbol ? get_color_scheme(color_scheme) : color_scheme

    for pos in 1:L
        _render_position!(ax, pos, @view(mat[pos, :]), alphabet, colors, font, sort_letters)
    end

    ax.xlabel = "Position"
    ax.ylabel = ylabel
    ax.xticks = 1:L
    Makie.xlims!(ax, 0.5, L + 0.5)

    return ax
end

function _render_position!(ax, pos, heights, alphabet, colors, font, sort_letters)
    C = length(alphabet)
    pairs = [(i, heights[i]) for i in 1:C if heights[i] > 0]
    sort_letters && sort!(pairs; by = last)

    y_offset = 0.0
    for (ci, h) in pairs
        glyph   = get_glyph(alphabet[ci]; font)
        polygon = glyph_to_polygon(glyph, pos - 0.5, y_offset, 1.0, h)
        Makie.poly!(ax, polygon; color = get_color(alphabet[ci], colors), strokewidth = 0)
        y_offset += h
    end
end

# --- Convenience constructors ---

"""
    seqlogo(matrix, alphabet; figsize=(800,300), kwargs...) -> Figure

Create a new `Figure`, plot the sequence logo, and return it.
"""
function seqlogo(matrix::AbstractMatrix, alphabet::AbstractVector{Char};
                  figsize::Tuple{Int,Int} = (800, 300), kwargs...)
    fig = Makie.Figure(; size = figsize)
    ax  = Makie.Axis(fig[1, 1])
    seqlogo!(ax, matrix, alphabet; kwargs...)
    return fig
end

"""
    seqlogo(sequences::Vector{String}; alphabet_name=:dna, matrix_type=:information, kwargs...) -> Figure

Build a matrix from aligned `sequences` and plot a sequence logo.

# Keyword arguments
- `alphabet_name`: `:dna`, `:rna`, or `:protein`.
- `matrix_type`: `:information` (default), `:probability`, `:counts`, or `:weight`.
- `pseudocount`: pseudocount added during probability estimation (default `0.0`).
- `background`: optional background frequency vector.
- Other keyword arguments are forwarded to `seqlogo!`.
"""
function seqlogo(sequences::Vector{String};
                  alphabet_name::Symbol = :dna,
                  matrix_type::Symbol = :information,
                  pseudocount::Float64 = 0.0,
                  background::Union{Nothing, Vector{Float64}} = nothing,
                  kwargs...)
    alpha = get_alphabet(alphabet_name)

    mat = if matrix_type === :information
        information_content(sequences, alpha; pseudocount, background)
    elseif matrix_type === :probability
        ppm(sequences, alpha; pseudocount)
    elseif matrix_type === :counts
        pfm(sequences, alpha)
    elseif matrix_type === :weight
        pwm(sequences, alpha; pseudocount = max(pseudocount, 0.001), background)
    else
        error("Unknown matrix_type: $matrix_type. Use :information, :probability, :counts, or :weight")
    end

    cs = alphabet_name in (:dna, :rna) ? :classic : :chemistry
    ylabel = if matrix_type === :information
        "Information content (bits)"
    elseif matrix_type === :probability
        "Probability"
    elseif matrix_type === :counts
        "Counts"
    else
        "Log-odds (bits)"
    end

    return seqlogo(mat, alpha; color_scheme = cs, ylabel, kwargs...)
end
