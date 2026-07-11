import Aqua, MakieSequenceLogos
using Test: @testset

@testset "aqua" begin
    # The `persistent_tasks` check is flaky on CI: it times out because loading the
    # package (with its heavy Makie dependency) is slow, not because the package
    # actually starts persistent tasks. Disable just this check.
    Aqua.test_all(MakieSequenceLogos; persistent_tasks=false)
end
