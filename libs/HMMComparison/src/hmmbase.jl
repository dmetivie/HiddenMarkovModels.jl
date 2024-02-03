struct HMMBaseImplem <: Implementation end

function HMMBenchmark.build_model(
    rng::AbstractRNG, implem::HMMBaseImplem; instance::Instance
)
    (; nb_states, obs_dim) = instance
    (; init, trans, means, stds) = build_params(rng; instance)

    a = init
    A = trans
    if obs_dim == 1
        B = [Normal(means[1, i], stds[1, i]) for i in 1:nb_states]
    else
        B = [MvNormal(means[:, i], Diagonal(stds[:, i])) for i in 1:nb_states]
    end

    hmm = HMMBase.HMM(a, A, B)
    return hmm
end

function HMMBenchmark.build_benchmarkables(
    rng::AbstractRNG, implem::HMMBaseImplem; instance::Instance, algos::Vector{String}
)
    (; obs_dim, seq_length, nb_seqs, bw_iter) = instance

    hmm = build_model(rng, implem; instance)
    data = randn(rng, nb_seqs, seq_length, obs_dim)

    if obs_dim == 1
        obs_mat = reduce(vcat, data[k, :, 1] for k in 1:nb_seqs)
    else
        obs_mat = reduce(vcat, data[k, :, :] for k in 1:nb_seqs)
    end

    benchs = BenchmarkGroup()

    if "logdensity" in algos
        benchs["logdensity"] = @benchmarkable begin
            HMMBase.forward($hmm, $obs_mat)
        end evals = 1 samples = 100
    end

    if "forward" in algos
        benchs["forward"] = @benchmarkable begin
            HMMBase.forward($hmm, $obs_mat)
        end evals = 1 samples = 100
    end

    if "viterbi" in algos
        benchs["viterbi"] = @benchmarkable begin
            HMMBase.viterbi($hmm, $obs_mat)
        end evals = 1 samples = 100
    end

    if "forward_backward" in algos
        benchs["forward_backward"] = @benchmarkable begin
            HMMBase.posteriors($hmm, $obs_mat)
        end evals = 1 samples = 100
    end

    if "baum_welch" in algos
        benchs["baum_welch"] = @benchmarkable begin
            HMMBase.fit_mle($hmm, $obs_mat; maxiter=$bw_iter, tol=-Inf)
        end evals = 1 samples = 100
    end

    return benchs
end