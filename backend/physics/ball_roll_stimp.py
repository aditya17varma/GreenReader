import numpy as np

G_FTPS2 = 32.174  # ft/s^2
DEFAULT_STIMP_LAUNCH_FPS = 6.0  # Stimpmeter exit speed proxy


class BallRollSimulatorStimp:
    """
    Ball roll on heightfield in FEET with Stimp-based rolling resistance.

    a_total = a_gravity + a_resist
      a_gravity = -g * grad(h)
      a_resist  = -a0 * v_hat    where a0 = v_stimp^2 / (2*stimp_ft)

    This makes a flat-green rollout consistent with the chosen stimp_ft.
    """

    def __init__(
        self,
        heightmap,
        stimp_ft: float,
        dt: float = 0.01,
        v_stimp_fps: float = DEFAULT_STIMP_LAUNCH_FPS,
        stop_speed_fps: float = 0.2,
        max_time_s: float = 30.0,
        cup_radius_ft: float = 2.125 / 12.0,  # 2.125 in
        max_cup_speed_fps: float = 4.0,       # simple "capture" threshold
    ):
        self.hm = heightmap
        self.dt = float(dt)
        self.stop_speed = float(stop_speed_fps)
        self.max_time = float(max_time_s)
        self.cup_r = float(cup_radius_ft)
        self.max_cup_speed = float(max_cup_speed_fps)

        self.stimp_ft = float(stimp_ft)
        self.v_stimp = float(v_stimp_fps)

        if self.stimp_ft <= 0:
            raise ValueError("stimp_ft must be positive")

        # constant resist decel magnitude on flat
        self.a0 = (self.v_stimp ** 2) / (2.0 * self.stimp_ft)

        if getattr(self.hm, "grad_x", None) is None or getattr(self.hm, "grad_z", None) is None:
            raise RuntimeError("HeightMap gradients not computed. Call hm.compute_gradients() first.")

    def _inside_green(self, x_ft: float, z_ft: float) -> bool:
        iz, ix = self.hm._index_of(x_ft, z_ft)
        return bool(self.hm.mask[iz, ix])

    def simulate(self, start_x_ft, start_z_ft, v0_x_fps, v0_z_fps, hole_x_ft=None, hole_z_ft=None):
        p = np.array([float(start_x_ft), float(start_z_ft)], dtype=float)
        v = np.array([float(v0_x_fps), float(v0_z_fps)], dtype=float)

        path_x, path_z, path_y = [], [], []
        holed = False
        t = 0.0

        steps = int(self.max_time / self.dt)
        for _ in range(steps):
            x, z = float(p[0]), float(p[1])

            if not self._inside_green(x, z):
                break

            y = self.hm.get_height_at(x, z)
            path_x.append(x)
            path_z.append(z)
            path_y.append(y)

            speed = float(np.linalg.norm(v))
            if speed < self.stop_speed:
                break

            # Hole check (capture)
            if hole_x_ft is not None and hole_z_ft is not None:
                d2 = (x - hole_x_ft) ** 2 + (z - hole_z_ft) ** 2
                if d2 <= self.cup_r ** 2 and speed <= self.max_cup_speed:
                    holed = True
                    break

            # Gravity along slope
            grad = self.hm.get_gradient_at(x, z)  # [dh/dx, dh/dz]
            a_gravity = -G_FTPS2 * grad

            # Rolling resistance opposite velocity direction
            vhat = v / (speed + 1e-12)
            a_resist = -self.a0 * vhat

            a = a_gravity + a_resist

            # semi-implicit Euler
            v = v + a * self.dt
            p = p + v * self.dt
            t += self.dt

        return {
            "path_x": np.array(path_x),
            "path_z": np.array(path_z),
            "path_y": np.array(path_y),
            "holed": holed,
            "t_end": t,
            "final_x": float(path_x[-1]) if path_x else float(start_x_ft),
            "final_z": float(path_z[-1]) if path_z else float(start_z_ft),
            "final_speed": float(np.linalg.norm(v)),
        }
