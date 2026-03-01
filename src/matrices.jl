# Sequence-to-matrix computations
#
# Convention: all matrices are q × L where q = |alphabet| and L = sequence length.
# Each column is one position; each row is one alphabet letter.

const DNA_ALPHABET = ['A', 'C', 'G', 'T']
const RNA_ALPHABET = ['A', 'C', 'G', 'U']
const PROTEIN_ALPHABET = collect("ACDEFGHIKLMNPQRSTVWY")

function get_alphabet(name::Symbol)
    name === :dna && return DNA_ALPHABET
    name === :rna && return RNA_ALPHABET
    name === :protein && return PROTEIN_ALPHABET
    error("Unknown alphabet: $name. Use :dna, :rna, or :protein")
end

"""
    pfm(sequences, alphabet) -> Matrix{Float64}

Position Frequency Matrix (raw counts).
Returns a `q × L` matrix (`q = length(alphabet)`, `L = sequence length`).
"""
function pfm(sequences::Vector{String}, alphabet::Vector{Char})
    L = length(sequences[1])
    all(s -> length(s) == L, sequences) || error("All sequences must have the same length")
    q = length(alphabet)
    char_to_idx = Dict(c => i for (i, c) in enumerate(alphabet))
    mat = zeros(Float64, q, L)
    for seq in sequences
        for (pos, ch) in enumerate(seq)
            idx = get(char_to_idx, ch, nothing)
            idx === nothing && continue
            mat[idx, pos] += 1.0
        end
    end
    return mat
end

"""
    ppm(sequences, alphabet; pseudocount=0.0) -> Matrix{Float64}

Position Probability Matrix (`q × L`).
`P[c,i] = (N[c,i] + pseudocount) / (N_i + q * pseudocount)`
"""
function ppm(sequences::Vector{String}, alphabet::Vector{Char}; pseudocount::Float64=0.0)
    counts = pfm(sequences, alphabet)
    q = length(alphabet)
    prob = similar(counts)
    for pos in axes(counts, 2)
        col_sum = sum(@view counts[:, pos]) + q * pseudocount
        for c in 1:q
            prob[c, pos] = (counts[c, pos] + pseudocount) / col_sum
        end
    end
    return prob
end

"""
    pwm(sequences, alphabet; pseudocount=0.001, background=nothing) -> Matrix{Float64}

Position Weight Matrix (log-odds, `q × L`).
`W[c,i] = log2(P[c,i] / Q[c])`
"""
function pwm(sequences::Vector{String}, alphabet::Vector{Char};
             pseudocount::Float64=0.001,
             background::Union{Nothing, Vector{Float64}}=nothing)
    prob = ppm(sequences, alphabet; pseudocount)
    q = length(alphabet)
    bg = background === nothing ? fill(1.0 / q, q) : background
    weight = similar(prob)
    for pos in axes(prob, 2)
        for c in 1:q
            weight[c, pos] = log2(prob[c, pos] / bg[c])
        end
    end
    return weight
end

"""
    information_content(sequences, alphabet; pseudocount=0.0, background=nothing) -> Matrix{Float64}

Information Content matrix (`q × L`).
`IC[c,i] = P[c,i] * KL_i` where `KL_i = Σ_c P[c,i] log2(P[c,i] / Q[c])`.
"""
function information_content(sequences::Vector{String}, alphabet::Vector{Char};
                              pseudocount::Float64=0.0,
                              background::Union{Nothing, Vector{Float64}}=nothing)
    prob = ppm(sequences, alphabet; pseudocount)
    q = length(alphabet)
    bg = background === nothing ? fill(1.0 / q, q) : background
    ic_mat = similar(prob)
    for pos in axes(prob, 2)
        kl = 0.0
        for c in 1:q
            p = prob[c, pos]
            p > 0 && (kl += p * log2(p / bg[c]))
        end
        for c in 1:q
            ic_mat[c, pos] = prob[c, pos] * kl
        end
    end
    return ic_mat
end

"""
    validate_matrix(matrix, alphabet) -> Matrix{Float64}

Check that `matrix` is `q × L` and return a dense `Float64` copy.
"""
function validate_matrix(matrix::AbstractMatrix, alphabet::AbstractVector{Char})
    size(matrix, 1) == length(alphabet) || error(
        "Matrix has $(size(matrix, 1)) rows but alphabet has $(length(alphabet)) characters"
    )
    return Matrix{Float64}(matrix)
end
