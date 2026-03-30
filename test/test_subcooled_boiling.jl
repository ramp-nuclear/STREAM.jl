using Test
using STREAM

# ─────────────────────────────────────────────────────────────────────────────
# Phase 28: Subcooled Boiling Correlations
# SCB-01: McAdams_SCB_heat_flux
# SCB-02: Bergles_Rohsenow_SCB_heat_flux
# SCB-03: partial_SCB_correction
# SCB-04: regime_dependent_q_scb
# ─────────────────────────────────────────────────────────────────────────────

@testset "Subcooled Boiling Correlations" begin

    @testset "SCB-01: McAdams_SCB_heat_flux" begin
        T_sat = 373.15  # 100C at ~1 atm
        # Positive heat flux for T_wall > T_sat
        q = McAdams_SCB_heat_flux(T_sat, T_sat + 10.0)
        @test q > 0.0
        @test q isa Float64
        # Zero for T_wall <= T_sat
        @test McAdams_SCB_heat_flux(T_sat, T_sat) == 0.0
        @test McAdams_SCB_heat_flux(T_sat, T_sat - 5.0) == 0.0
        # Monotonicity: higher dT -> higher q
        q1 = McAdams_SCB_heat_flux(T_sat, T_sat + 5.0)
        q2 = McAdams_SCB_heat_flux(T_sat, T_sat + 10.0)
        q3 = McAdams_SCB_heat_flux(T_sat, T_sat + 20.0)
        @test q1 < q2 < q3
    end

    @testset "SCB-02: Bergles_Rohsenow_SCB_heat_flux" begin
        T_sat = 373.15
        pressure = 1e5  # 1 bar
        # Positive heat flux for T_wall > T_sat
        q = Bergles_Rohsenow_SCB_heat_flux(T_sat + 10.0, T_sat, pressure)
        @test q > 0.0
        @test q isa Float64
        # Zero for T_wall <= T_sat
        @test Bergles_Rohsenow_SCB_heat_flux(T_sat, T_sat, pressure) == 0.0
        @test Bergles_Rohsenow_SCB_heat_flux(T_sat - 5.0, T_sat, pressure) == 0.0
        # Accepts kwargs without error
        q_kw = Bergles_Rohsenow_SCB_heat_flux(T_sat + 10.0, T_sat, pressure; h_fg=2257e3, sigma=0.059)
        @test q_kw == q  # defaults match explicit values
        # Pressure sensitivity: different pressure gives different result
        q_2bar = Bergles_Rohsenow_SCB_heat_flux(T_sat + 10.0, T_sat, 2e5)
        @test q_2bar != q  # pressure changes the result
    end

    @testset "SCB-03: partial_SCB_correction" begin
        # Inside boiling: factor > 1.0
        factor = partial_SCB_correction(1e4, 2e4, 5e3)
        @test factor > 1.0
        # Outside boiling (q_scb <= q_scb_inc): factor = 1.0
        @test partial_SCB_correction(1e4, 5e3, 5e3) == 1.0
        @test partial_SCB_correction(1e4, 3e3, 5e3) == 1.0
        # q_spl = 0 safety: factor = 1.0
        @test partial_SCB_correction(0.0, 1e4, 5e3) == 1.0
        # Negative q_spl safety
        @test partial_SCB_correction(-100.0, 1e4, 5e3) == 1.0
    end

    @testset "SCB-04: regime_dependent_q_scb" begin
        T_sat = 373.15
        T_wall = T_sat + 10.0
        pressure = 1e5
        # Factory returns a callable
        scb_fn = regime_dependent_q_scb(pressure=pressure)
        @test scb_fn isa Function
        # Turbulent (Re >= 2300): returns McAdams value
        q_turb = scb_fn(T_wall, T_sat, 5000.0)
        q_mcadams = McAdams_SCB_heat_flux(T_sat, T_wall)
        @test q_turb == q_mcadams
        # Laminar (Re < 2300): returns Bergles-Rohsenow value
        q_lam = scb_fn(T_wall, T_sat, 1000.0)
        q_br = Bergles_Rohsenow_SCB_heat_flux(T_wall, T_sat, pressure)
        @test q_lam == q_br
        # Custom Re_transition shifts cutoff
        scb_fn2 = regime_dependent_q_scb(pressure=pressure, Re_transition=5000)
        @test scb_fn2(T_wall, T_sat, 3000.0) == q_br  # now laminar at Re=3000
    end
end
