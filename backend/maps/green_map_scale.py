import numpy as np
from dataclasses import dataclass

@dataclass(frozen=True)
class PixelToFeetTransform:
    """
    Maps image pixels (u,v) to green-local feet (x,z).

    Convention:
      - u increases to the right
      - v increases downward
      - x increases to the right
      - z increases upward  (so we invert v)

    Image coordinate origin is top-left (0,0).
    Green-local origin (0,0) is the image center.
    """
    img_w_px: int
    img_h_px: int
    green_width_ft: float   # full width left↔right
    green_height_ft: float  # full height top↔bottom

    @property
    def ft_per_px_x(self) -> float:
        return self.green_width_ft / self.img_w_px

    @property
    def ft_per_px_z(self) -> float:
        return self.green_height_ft / self.img_h_px

    def uv_to_xz(self, u_px: float, v_px: float) -> tuple[float, float]:
        # center pixel coords
        cu = u_px - (self.img_w_px / 2.0)
        cv = v_px - (self.img_h_px / 2.0)

        x_ft = cu * self.ft_per_px_x
        z_ft = -cv * self.ft_per_px_z  # invert: image down is -z
        return float(x_ft), float(z_ft)

    def xz_to_uv(self, x_ft: float, z_ft: float) -> tuple[float, float]:
        u = (x_ft / self.ft_per_px_x) + (self.img_w_px / 2.0)
        v = (-z_ft / self.ft_per_px_z) + (self.img_h_px / 2.0)
        return float(u), float(v)


def make_local_grid_ft(green_width_ft: float, green_height_ft: float, resolution_ft: float):
    """
    Make an (X,Z) grid in feet centered at (0,0).
    """
    x = np.arange(-green_width_ft/2, green_width_ft/2 + resolution_ft, resolution_ft)
    z = np.arange(-green_height_ft/2, green_height_ft/2 + resolution_ft, resolution_ft)
    X, Z = np.meshgrid(x, z)
    return X, Z