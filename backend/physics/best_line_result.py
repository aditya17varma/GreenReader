from __future__ import annotations
from dataclasses import dataclass, asdict
from typing import Any, Dict, List, Optional
import math
import numpy as np


@dataclass(frozen=True)
class BestLineResult:
    stimp_ft: float
    ball_x_ft: float
    ball_z_ft: float
    hole_x_ft: float
    hole_z_ft: float

    # Recommended launch
    aim_angle_deg: float          # absolute aim angle in degrees (x-axis=0°, CCW positive)
    aim_offset_deg: float         # relative to straight-to-hole
    v0_speed_fps: float
    v0_x_fps: float
    v0_z_fps: float

    # Outcome
    holed: bool
    miss_ft: float
    t_end_s: float
    final_x_ft: float
    final_z_ft: float

    # Path
    path_x_ft: List[float]
    path_z_ft: List[float]
    path_y_ft: List[float]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @staticmethod
    def compute_abs_angle_deg(vx: float, vz: float) -> float:
        # angle in x-z plane; 0 deg points +x (east), 90 deg points +z (north)
        return math.degrees(math.atan2(vz, vx))

    @staticmethod
    def from_best_and_context(
        *,
        stimp_ft: float,
        ball_x_ft: float,
        ball_z_ft: float,
        hole_x_ft: float,
        hole_z_ft: float,
        best: Dict[str, Any],
    ) -> "BestLineResult":
        vx = float(best["v0_x_fps"])
        vz = float(best["v0_z_fps"])
        speed = float(best["speed_fps"])
        aim_abs = BestLineResult.compute_abs_angle_deg(vx, vz)

        res = best["result"]
        return BestLineResult(
            stimp_ft=float(stimp_ft),
            ball_x_ft=float(ball_x_ft),
            ball_z_ft=float(ball_z_ft),
            hole_x_ft=float(hole_x_ft),
            hole_z_ft=float(hole_z_ft),

            aim_angle_deg=float(aim_abs),
            aim_offset_deg=float(best["angle_deg"]),
            v0_speed_fps=float(speed),
            v0_x_fps=vx,
            v0_z_fps=vz,

            holed=bool(res["holed"]),
            miss_ft=float(best["miss_ft"]),
            t_end_s=float(res["t_end"]),
            final_x_ft=float(res["final_x"]),
            final_z_ft=float(res["final_z"]),

            path_x_ft=[float(x) for x in res["path_x"]],
            path_z_ft=[float(z) for z in res["path_z"]],
            path_y_ft=[float(y) for y in res["path_y"]],
        )
