using Knet
using Gym
using DeepRL
using ArgParse
import AutoGrad: getval

const F = Float64

function main(args)
    s = ArgParseSettings()
    s.description = ""

    @add_arg_table s begin
        ("--hidden"; default=[100]; nargs='*'; arg_type=Int64)
        ("--atype"; default=(gpu()>=0 ? "KnetArray{Float32}":"Array{Float64}"))
        ("--optim"; default="Adam(;lr=1e-2)")
        ("--discount"; default=0.99; arg_type=Float64)
        ("--episodes"; default=500; arg_type=Int64)
        ("--rendered"; default=true; arg_type=Bool)
        ("--seed"; default=-1; arg_type=Int64)
        ("--period"; default=50; arg_type=Int64)
    end

    isa(args, String) && (args = split(args))
    o = parse_args(args, s; as_symbols=true); println(o)
    o[:atype] = eval(parse(o[:atype]))
    
    env = GymEnv("CartPole-v1")
    o[:seed] > 0 && (srand(o[:seed]); srand(env, o[:seed]))
    xsize, ysize = 4, 2 
    w = initweights(o[:atype], o[:hidden], xsize, ysize)
    opts = map(wi->eval(parse(o[:optim])), w)

    avgreward = 0
    for k = 1:o[:episodes]
        state = reset!(env)
        episode_rewards = 0
        history = History()
        for t=1:1000
            s = convert(o[:atype], state)
            pred = predict(w,s)
            probs = softmax(pred)
            action = sample_action(probs)

            next_state, reward, done, _ = step!(env, actions(env)[action])
            append!(history.states, state)
            push!(history.actions, action)
            push!(history.rewards, reward)
            state = next_state
            episode_rewards += reward

            k % o[:period] == 0 && o[:rendered] && render(env)
            done && break
        end

        avgreward = 0.01 * episode_rewards + avgreward * 0.99

        k % o[:period] == 0 && println("(episode:$k, avgreward:$avgreward)")
        k % o[:period] == 0 && o[:rendered] && render(env, close=true)

        states = reshape(history.states, xsize, length(history.states)÷xsize)
        values = get_values(history.rewards, o[:discount])
        train!(w, states, history.actions, values, opts)
    end
end

 mutable struct History
    states::Vector{F}
    actions::Vector{Int}
    rewards::Vector{F}
end
History() = History(zeros(F,0),zeros(Int, 0),zeros(F,0))

function initweights(atype, hidden, xsize=4, ysize=2)
    w = []
    x = xsize
    for y in [hidden..., ysize]
        push!(w, xavier(y, x))
        push!(w, zeros(y, 1))
        x = y
    end
    return map(wi->convert(atype,wi), w)
end

function predict(w,x)
    # @show size(w) size(x)
    for i = 1:2:length(w)-2
        x = relu.(w[i] * x .+ w[i+1])
    end
    return w[end-1] * x .+ w[end]
end

function softmax(x)
    y = maximum(x, 1)
    y = x .- y
    y = exp.(y)
    return y ./ sum(y, 1)
end

function sample_action(probs)
    probs = Array(probs)
    cprobs = cumsum(probs)
    sampled = cprobs .> rand()
    actions = mapslices(indmax, sampled, 1)
    return actions[1]
end

function get_values(rewards, γ)
    values = similar(rewards)
    values[end] = rewards[end]
    for k = length(rewards)-1:-1:1
        values[k] = γ * values[k+1] + rewards[k]
    end

    return (values .- mean(values)) ./ (std(values) + F(1e-8))
end

function loss(w, x, actions, values)
    # @show size(x)
    ypred = predict(w,x)
    nrows, ncols = size(ypred)
    index = actions + nrows*(0:(length(actions)-1))
    # @show size(ypred) actions values index
    lp = logp(ypred, 1)[index]
    return -sum(lp .* values) / size(x, 2)
end

function train!(w, s, a, v, opt)
    dw = grad(loss)(w, s, a, v)
    update!(w, dw, opt)
end

!isinteractive() && main(ARGS)
