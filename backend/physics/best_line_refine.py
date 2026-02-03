import numpy as np


def _simulate_score(sim, ball_x, ball_z, hole_x, hole_z, v0):
    res = sim.simulate(
        start_x_ft=ball_x,
        start_z_ft=ball_z,
        v0_x_fps=float(v0[0]),
        v0_z_fps=float(v0[1]),
        hole_x_ft=hole_x,
        hole_z_ft=hole_z,
    )

    fx, fz = res["final_x"], res["final_z"]
    miss = float(np.hypot(fx - hole_x, fz - hole_z))

    # Penalize big blow-bys (if not holed)
    # This discourages lines that "almost go in" but rocket past.
    final_speed = float(res.get("final_speed", 0.0))
    blowby_penalty = 0.0 if res["holed"] else 0.15 * final_speed

    if res["holed"]:
        score = -1000.0 - miss
    else:
        score = miss + blowby_penalty

    return score, miss, res


def best_line_coarse_to_fine(
    sim,
    ball_x_ft: float,
    ball_z_ft: float,
    hole_x_ft: float,
    hole_z_ft: float,
    angle_span_deg: float = 25.0,
    speed_bounds_fps=(2.0, 16.0),
):
    """
    Coarse-to-fine search over (angle_offset, speed).

    Stages:
      1) coarse angle sweep + coarse speed sweep
      2) refine around best (smaller steps)
      3) final micro-refine

    Returns:
      dict with best params + result.
    """

    to_hole = np.array([hole_x_ft - ball_x_ft, hole_z_ft - ball_z_ft], dtype=float)
    base_ang = np.arctan2(to_hole[1], to_hole[0])

    def run_grid(angle_step, speed_step, center_angle_deg, center_speed, angle_window_deg, speed_window):
        best = None
        angs = np.arange(center_angle_deg - angle_window_deg,
                         center_angle_deg + angle_window_deg + 1e-9,
                         angle_step)
        vmin, vmax = speed_window
        speeds = np.arange(vmin, vmax + 1e-9, speed_step)

        for a_deg in angs:
            ang = base_ang + np.deg2rad(a_deg)
            d = np.array([np.cos(ang), np.sin(ang)], dtype=float)

            for s in speeds:
                v0 = d * float(s)
                score, miss, res = _simulate_score(sim, ball_x_ft, ball_z_ft, hole_x_ft, hole_z_ft, v0)

                if best is None or score < best["score"]:
                    best = {
                        "angle_deg": float(a_deg),
                        "speed_fps": float(s),
                        "v0_x_fps": float(v0[0]),
                        "v0_z_fps": float(v0[1]),
                        "score": float(score),
                        "miss_ft": float(miss),
                        "result": res,
                    }
        return best

    # Stage 1: coarse
    best1 = run_grid(
        angle_step=2.0,
        speed_step=1.0,
        center_angle_deg=0.0,
        center_speed=(speed_bounds_fps[0] + speed_bounds_fps[1]) / 2.0,
        angle_window_deg=angle_span_deg,
        speed_window=speed_bounds_fps,
    )

    # Stage 2: refine around best
    a2 = best1["angle_deg"]
    s2 = best1["speed_fps"]
    best2 = run_grid(
        angle_step=0.5,
        speed_step=0.25,
        center_angle_deg=a2,
        center_speed=s2,
        angle_window_deg=4.0,
        speed_window=(max(speed_bounds_fps[0], s2 - 2.0), min(speed_bounds_fps[1], s2 + 2.0)),
    )

    # Stage 3: micro refine
    a3 = best2["angle_deg"]
    s3 = best2["speed_fps"]
    best3 = run_grid(
        angle_step=0.2,
        speed_step=0.1,
        center_angle_deg=a3,
        center_speed=s3,
        angle_window_deg=1.0,
        speed_window=(max(speed_bounds_fps[0], s3 - 0.6), min(speed_bounds_fps[1], s3 + 0.6)),
    )

    return best3
