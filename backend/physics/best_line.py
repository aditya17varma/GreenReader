import numpy as np


def best_line_grid_search(
    sim,
    ball_x_ft: float,
    ball_z_ft: float,
    hole_x_ft: float,
    hole_z_ft: float,
    angle_span_deg: float = 25.0,
    angle_step_deg: float = 1.0,
    speed_min_fps: float = 2.0,
    speed_max_fps: float = 16.0,
    speed_step_fps: float = 0.5,
):
    """
    Returns:
      best: dict with v0, angle_deg, speed, result, score
      all_results: list of (angle_deg, speed, score, holed, miss_ft)
    """
    to_hole = np.array([hole_x_ft - ball_x_ft, hole_z_ft - ball_z_ft], dtype=float)
    base_angle = np.arctan2(to_hole[1], to_hole[0])  # radians (z over x)

    best = None
    all_results = []

    angles = np.arange(-angle_span_deg, angle_span_deg + 1e-9, angle_step_deg)
    speeds = np.arange(speed_min_fps, speed_max_fps + 1e-9, speed_step_fps)

    for a_deg in angles:
        ang = base_angle + np.deg2rad(a_deg)
        dir_vec = np.array([np.cos(ang), np.sin(ang)], dtype=float)

        for speed in speeds:
            v0 = dir_vec * float(speed)

            res = sim.simulate(
                start_x_ft=ball_x_ft,
                start_z_ft=ball_z_ft,
                v0_x_fps=float(v0[0]),
                v0_z_fps=float(v0[1]),
                hole_x_ft=hole_x_ft,
                hole_z_ft=hole_z_ft,
            )

            fx, fz = res["final_x"], res["final_z"]
            miss = float(np.hypot(fx - hole_x_ft, fz - hole_z_ft))

            # Score: holed is best; otherwise minimize miss distance
            # You can add more terms later (e.g., avoid big blow-bys)
            if res["holed"]:
                score = -1000.0 - miss  # massive bonus
            else:
                score = miss

            all_results.append((float(a_deg), float(speed), float(score), bool(res["holed"]), float(miss)))

            if best is None or score < best["score"]:
                best = {
                    "angle_deg": float(a_deg),
                    "speed_fps": float(speed),
                    "v0_x_fps": float(v0[0]),
                    "v0_z_fps": float(v0[1]),
                    "score": float(score),
                    "miss_ft": float(miss),
                    "result": res,
                }

    return best, all_results
