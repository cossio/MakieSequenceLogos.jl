# Sequence-to-matrix computations

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
Returns matrix of size (sequence_length, length(alphabet)).
"""
function pfm(sequences::Vector{String}, alphabet::Vector{Char})
    L = length(sequences[1])
    all(s -> length(s) == L, sequences) || error("All sequences must have the same length")
    C = length(alphabet)
    char_to_idx = Dict(c => i for (i, c) in enumerate(alphabet))
    mat = zeros(Float64, L, C)
    for seq in sequences
        for (pos, ch) in enumerate(seq)
            idx = get(char_to_idx, ch, nothing)
            idx === nothing && continue
            mat[pos, idx] += 1.0
        end
    end
    return mat
end

"""
    ppm(sequences, alphabet; pseudocount=0) -> Matrix{Real}

Position Probability Matrix.
P_ic = (N_ic + pseudocount) / (N_i + |alphabet| * pseudocount)
"""
function ppm(sequences::AbstractVector{String}, alphabet::AbstractVector{Char}; pseudocount::Real=0)
    counts = pfm(sequences, alphabet)
    C = length(alphabet)
    prob = similar(counts)
    for i = axes(counts, 1)
        row_sum = sum(@view counts[i, :]) + C * pseudocount
        for j = 1:C
            prob[i, j] = (counts[i, j] + pseudocount) / row_sum
        end
    end
    return prob
end

"""
    pwm(sequences, alphabet; pseudocount=0.001, background=nothing) -> Matrix{Float64}

Position Weight Matrix (log-odds).
W_ic = log2(P_ic / Q_c)
"""
function pwm(
    sequences::AbstractVector{String}, alphabet::AbstractVector{Char};
    pseudocount::Real=0.001,
    background::Union{Nothing, AbstractVector{Float64}} = nothing
)
    prob = ppm(sequences, alphabet; pseudocount)
    C = length(alphabet)
    bg = background === nothing ? fill(1.0 / C, C) : background
    weight = similar(prob)
    for i in axes(prob, 1)
        for j in 1:C
            weight[i, j] = log2(prob[i, j] / bg[j])
        end
    end
    return weight
end

"""
    information_content(sequences, alphabet; pseudocount=0.0, background=nothing) -> Matrix{Float64}

Information Content matrix.
Height of character c at position i = P_ic * IC_i
where IC_i = sum_c P_ic * log2(P_ic / Q_c)  (KL divergence from background)
"""
function information_content(
    sequences::Vector{String}, alphabet::Vector{Char};
    pseudocount::Float64=0.0, background::Union{Nothing, Vector{Float64}} = nothing
)
    prob = ppm(sequences, alphabet; pseudocount)
    C = length(alphabet)
    bg = background === nothing ? fill(1.0 / C, C) : background
    ic_mat = similar(prob)
    for i in axes(prob, 1)
        # KL divergence at position i
        kl = 0.0
        for j in 1:C
            p = prob[i, j]
            p > 0 && (kl += p * log2(p / bg[j]))
        end
        for j in 1:C
            ic_mat[i, j] = prob[i, j] * kl
        end
    end
    return ic_mat
end

function validate_matrix(matrix::AbstractMatrix, alphabet::AbstractVector{Char})
    size(matrix, 2) == length(alphabet) || error(
        "Matrix has $(size(matrix, 2)) columns but alphabet has $(length(alphabet)) characters"
    )
    return Matrix{Float64}(matrix)
end
