"""
    STREAMMeasurementsExt

[`UQ.measurements`](@ref STREAM.UQ.measurements), loaded with Measurements.jl.
"""
module STREAMMeasurementsExt

using Measurements: measurement
using STREAM.UQ: UQ, UQModel, as_absolute, jacobian

function UQ.measurements(model::UQModel, uncertainties::Pair...)
    outputs = measurement.(model.nominal, 0.0)
    for (parameter, uncertainty) in uncertainties
        J = jacobian(model, parameter)
        systematic, σ = as_absolute(uncertainty, model.values[UQ._position(model, parameter)])
        all(iszero, systematic) || throw(ArgumentError(
            "the uncertainty of $parameter has a systematic part, and a Measurement carries a " *
            "standard deviation only. uq returns the systematic part.",
        ))
        outputs = outputs .+ J * measurement.(0.0, UQ._entries(σ, size(J, 2)))
    end
    return outputs
end

end
