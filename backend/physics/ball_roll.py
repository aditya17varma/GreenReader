import numpy as np

G_FTPS2 = 32.174  # gravity in ft/s^2


class BallRollSimulator:
    """
    Simulate a golf ball rolling on a heightfield h(x,z) in FEET.

    State:
      p = (x,z) in feet
      v = (vx,vz) in ft/s

    Dynamics:
      a = -g * grad(h)  - k * v

    Notes:
      - grad(h) = (dh/dx, dh/dz) in (ft/ft), dimensionless slope
      - -g*grad(h) accelerates downhill
      - k controls rolling resistance (1/s). Larger k = ball stops sooner.
    """

    def __init__(
        self,
        heightmap,
        dt: float = 0.01,
        k_resist: float = 0.8,  # 1/s (tune)
        stop_speed_fps: float = 0.2,  # ft/s
        max_time_s: float = 20.0,
        cup_radius_ft: float = 2.125 / 12.0,  # 2.125 inches
    ):
        self.hm = heightmap
        self.dt = float(dt)
        self.k = float(k_resist)
        self.stop_speed = float(stop_speed_fps)
        self.max_time = float(max_time_s)
        self.cup_r = float(cup_radius_ft)

        if getattr(self.hm, "grad_x", None) is None or getattr(self.hm, "grad_z", None) is None:
            raise RuntimeError("HeightMap gradients not computed. Call hm.compute_gradients() first.")

    def _inside_green(self, x_ft: float, z_ft: float) -> bool:
        # nearest index and mask check
        iz, ix = self.hm._index_of(x_ft, z_ft)
        return bool(self.hm.mask[iz, ix])

    def simulate(
        self,
        start_x_ft: float,
        start_z_ft: float,
        v0_x_fps: float,
        v0_z_fps: float,
        hole_x_ft: float | None = None,
        hole_z_ft: float | None = None,
    ):
        """
        Returns dict with:
          path_x, path_z, path_y (arrays)
          holed (bool)
          t_end (float)
        """
        p = np.array([float(start_x_ft), float(start_z_ft)], dtype=float)
        v = np.array([float(v0_x_fps), float(v0_z_fps)], dtype=float)

        path_x = []
        path_z = []
        path_y = []

        holed = False
        t = 0.0

        steps = int(self.max_time / self.dt)
        for _ in range(steps):
            x, z = float(p[0]), float(p[1])

            # Stop if ball leaves green
            if not self._inside_green(x, z):
                break

            y = self.hm.get_height_at(x, z)
            path_x.append(x)
            path_z.append(z)
            path_y.append(y)

            # Hole check (optional)
            if hole_x_ft is not None and hole_z_ft is not None:
                if (x - hole_x_ft) ** 2 + (z - hole_z_ft) ** 2 <= self.cup_r ** 2:
                    holed = True
                    break

            speed = float(np.linalg.norm(v))
            if speed < self.stop_speed:
                break

            # Downhill acceleration from slope
            grad = self.hm.get_gradient_at(x, z)  # [dh/dx, dh/dz]
            a_gravity = -G_FTPS2 * grad  # downhill

            # Rolling resistance (linear damping)
            a_resist = -self.k * v

            a = a_gravity + a_resist

            # Semi-implicit Euler
            v = v + a * self.dt
            p = p + v * self.dt

            t += self.dt

        return {
            "path_x": np.array(path_x),
            "path_z": np.array(path_z),
            "path_y": np.array(path_y),
            "holed": holed,
            "t_end": t,
        }
