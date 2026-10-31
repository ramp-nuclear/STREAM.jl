"""
    STREAMMeasurementsExt

[`UQ.measurements`](@ref STREAM.UQ.measurements), loaded with Measurements.jl.
"""
module STREAMMeasurementsExt

using Measurements: measurement
using STREAM.UQ: UQ, LocalSensitivities, as_absolute, jacobian

function UQ.measurements(s::LocalSensitivities, uncertainties::Pair...)
    outputs = measurement.(s.nominal, 0.0)
    for (parameter, uncertainty) in uncertainties
        J = jacobian(s, parameter)
        systematic, σ = as_absolute(uncertainty, s.values[UQ._position(s.parameters, parameter)])
        all(iszero, systematic) || throw(ArgumentError(
            "the uncertainty of $parameter has a systematic part, and a Measurement carries a " *
            "standard deviation only. uq returns the systematic part.",
        ))
        outputs = outputs .+ J * measurement.(0.0, UQ._entries(σ, size(J, 2)))
    end
    return outputs
end

end
