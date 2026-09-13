# A small two-type pool LOFA case for test.jl: six axial cells and placeholder numbers
# sized so the loop closes. The riser is as tall as the core, so the hydrostatic heads
# cancel around the loop; the low-power type is throttled harder at its orifice; the pump
# head matches the loop drop at design flow, which lands both types within 2% of their
# design flows. None of it describes a plant. Guarded so test files that each include it can
# share one definition.
#! format: off
if !@isdefined(POOL_LOFA_TEST_CASE)
    const POOL_LOFA_TEST_CASE = (
        L=0.6, n=6, nx=2,
        rho_s=2700.0, cp_s=900.0, k_s=180.0,
        T_pool=35.0, p_pool=1.7e5, P_rated=2.0e6,
        dP_pump=3.9e4, flywheel_L_over_A=2.5e4, primary_dp=3.0e4,
        riser_L=0.6, riser_D=0.3,
        flapper_open_at=1.5, flapper_f=1.0, flapper_area=0.03, flapper_open_time=2.0,
        trip_fraction=0.85,
        Lambda=U235_LAMBDA, beta_k=U235_BETA_K, lambda_k=U235_LAMBDA_K,
        types=(
            high=(N=40, width=0.066, gap=0.0027, heated_width=0.063,
                  plate_thickness=0.00127, ppf=1.4, power_fraction=0.9,
                  orifice_dp=2.0e3, design_ṁ=0.356),
            low=(N=10, width=0.066, gap=0.0027, heated_width=0.063,
                 plate_thickness=0.00127, ppf=1.3, power_fraction=0.1,
                 orifice_dp=7.9e3, design_ṁ=0.1),
        ),
    )
end
#! format: on
