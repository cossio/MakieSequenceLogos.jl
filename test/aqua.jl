import Aqua, MakieSequenceLogos
using Test: @testset

@testset "aqua" begin
    # `persistent_tasks` spawns a subprocess that loads the package and waits for a
    # `done.log` file. With the heavy Makie dependency, loading routinely exceeds the
    # check's timeout on CI, so `done.log` is never created and the test errors even
    # though the package starts no persistent tasks. Disable this flaky check.
    Aqua.test_all(MakieSequenceLogos; persistent_tasks=false)
end
