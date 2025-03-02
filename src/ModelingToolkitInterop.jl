""" Supports conversion from PetriNets to ModelingToolkit ODESystems

This provides access to the ModelingToolkit library.
"""

module ModelingToolkitInterop

  using AlgebraicPetri
  using AlgebraicPetri.BilayerNetworks
  using Catlab.CategoricalAlgebra: has_subpart, incident, parts
  using ...ModelingToolkit
  import ...ModelingToolkit: ODESystem


  """ Convert a general PetriNet to an ODESystem
  This conversion forgets any labels or rates provided, and converts all
  parameters and variables into symbols. It does preserve the ordering of
  transitions and states though (Transition 1 has a rate of k[1], state 1 has a
  concentration of S[1])
  """
  function ModelingToolkit.ODESystem(p::AbstractPetriNet; name=:PetriNet)
    t = first(@variables t)

    sname′(i) =
      if has_subpart(p, :sname)
        sname(p, i)
      else
        Symbol("S", i)
      end
    tname′(i) =
      if has_subpart(p, :tname)
        tname(p, i)
      else
        Symbol("r", i)
      end

    S = [first(@variables $Si(t)) for Si in sname′.(1:ns(p))]
    r = [first(@parameters $ri) for ri in tname′.(1:nt(p))]
    D = Differential(t)

    tm = TransitionMatrices(p)

    coefficients = tm.output - tm.input

    transition_rates = [r[tr] * prod(S[s]^tm.input[tr, s] for s in 1:ns(p)) for tr in 1:nt(p)]

    eqs = [D(S[s]) ~ transition_rates' * coefficients[:, s] for s in 1:ns(p)]

    ODESystem(eqs, t, S, r, name=name)
  end

  """ Convert a general Bilayer Network to an ODESystem
  This conversion forgets any labels or rates provided, and converts all
  parameters and variables into symbols. It does preserve the ordering of
  transitions and states though (Transition 1 has a rate of k[1], state 1 has a
  concentration of S[1])
  """
  function ModelingToolkit.ODESystem(bn::Union{AbstractLabelledBilayerNetwork,AbstractBilayerNetwork}; name=:BilayerNetwork)
    t = (@variables t)[1]
    D = Differential(t)
    symbolic_vars = map(bn[:variable]) do v
      (@variables $v(t))[1]
    end
    symbolic_params = map(bn[:parameter]) do p
      (@parameters $p)[1]
    end

    ϕs = map(parts(bn, :Box)) do b
      p = symbolic_params[b]
      vars = mapreduce(*, incident(bn, b, :call), init=p) do i
        j = bn[i, :arg]
        return symbolic_vars[j]
      end
    end

    infs = map(parts(bn, :Qout)) do tv
      flux = mapreduce(+, incident(bn, tv, :infusion), init=0) do wa
        j = bn[wa, :influx]
        return ϕs[j]
      end
      flux -= mapreduce(+, incident(bn, tv, :effusion), init=0) do wa
        j = bn[wa, :efflux]
        return ϕs[j]
      end
    end

    # We assume bn[:tanvar] ⊆ bn[:variable] here
    tanvar_idxs = indexin(bn[:tanvar], bn[:variable])
    zparts = zip(tanvar_idxs, infs)

    eqs = Equation[D(symbolic_vars[j::Int]) ~ rhs for (j, rhs) in zparts]
    ODESystem(eqs, t, symbolic_vars, symbolic_params, name=name)
  end

end
