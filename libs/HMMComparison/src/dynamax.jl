struct dynamaxImplem <: Implementation end

function HMMBenchmark.build_model(
    rng::AbstractRNG, implem::dynamaxImplem; instance::Instance
)
    np = pyimport("numpy")
    jnp = pyimport("jax.numpy")
    dynamax_hmm = pyimport("dynamax.hidden_markov_model")

    (; nb_states, obs_dim) = instance
    (; init, trans, means, stds) = build_params(rng; instance)

    initial_probs = jnp.array(Py(init).to_numpy())
    transition_matrix = jnp.array(Py(trans).to_numpy())
    emission_means = jnp.array(Py(transpose(means)).to_numpy())
    emission_scale_diags = jnp.array(Py(transpose(stds)).to_numpy())

    hmm = dynamax_hmm.DiagonalGaussianHMM(nb_states, obs_dim)
    params, props = hmm.initialize(;
        initial_probs=initial_probs,
        transition_matrix=transition_matrix,
        emission_means=emission_means,
        emission_scale_diags=emission_scale_diags,
    )

    return hmm, params, props
end

function HMMBenchmark.build_benchmarkables(
    rng::AbstractRNG, implem::dynamaxImplem; instance::Instance, algos::Vector{String}
)
    np = pyimport("numpy")
    jax = pyimport("jax")
    jnp = pyimport("jax.numpy")
    (; obs_dim, seq_length, nb_seqs, bw_iter) = instance

    hmm, params, _ = build_model(rng, implem; instance)
    data = randn(rng, nb_seqs, seq_length, obs_dim)

    obs_tens_py = jnp.array(Py(data).to_numpy())

    benchs = Dict()

    if "logdensity" in algos
        filter_vmap = jax.jit(jax.vmap(hmm.filter; in_axes=pylist((pybuiltins.None, 0))))
        benchs["logdensity"] = @benchmarkable begin
            $(filter_vmap)($params, $obs_tens_py)
        end evals = 1 samples = 100
    end

    if "forward" in algos
        filter_vmap = jax.jit(jax.vmap(hmm.filter; in_axes=pylist((pybuiltins.None, 0))))
        benchs["forward"] = @benchmarkable begin
            $(filter_vmap)($params, $obs_tens_py)
        end evals = 1 samples = 100
    end

    if "viterbi" in algos
        most_likely_states_vmap = jax.jit(
            jax.vmap(hmm.most_likely_states; in_axes=pylist((pybuiltins.None, 0)))
        )
        benchs["viterbi"] = @benchmarkable begin
            $(most_likely_states_vmap)($params, $obs_tens_py)
        end evals = 1 samples = 100
    end

    if "forward_backward" in algos
        smoother_vmap = jax.jit(
            jax.vmap(hmm.smoother; in_axes=pylist((pybuiltins.None, 0)))
        )
        benchs["forward_backward"] = @benchmarkable begin
            $(smoother_vmap)($params, $obs_tens_py)
        end evals = 1 samples = 100
    end

    if "baum_welch" in algos
        benchs["baum_welch"] = @benchmarkable begin
            hmm_guess.fit_em(
                params_guess, props_guess, $obs_tens_py; num_iters=$bw_iter, verbose=false
            )
        end evals = 1 samples = 100 setup = (
            tup = build_model($rng, $implem; instance=$instance);
            hmm_guess = tup[1];
            params_guess = tup[2];
            props_guess = tup[3]
        )
    end

    return benchs
end