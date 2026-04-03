import Aqua, MakieSequenceLogos
using Test: @testset

@testset "aqua" begin
    Aqua.test_all(MakieSequenceLogos; persistent_tasks = false)
end
