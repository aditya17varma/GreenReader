import numpy as np


class HeightMap:
    """
    HeightMap in FEET.

    Coordinate system:
      - X (feet): left/right
      - Z (feet): forward/back
      - Y (feet): elevation (up)
    """

    def __init__(self, X: np.ndarray, Z: np.ndarray, Y: np.ndarray, resolution_ft: float, mask: np.ndarray | None = None):
        if X.shape != Z.shape or X.shape != Y.shape:
            raise ValueError("X, Z, Y must have the same shape")

        self.X = X
        self.Z = Z
        self.Y = Y
        self.resolution_ft = float(resolution_ft)

        self.mask = mask  # True where valid (inside green)
        if self.mask is None:
            self.mask = ~np.isnan(self.Y)

        # Gradients
        self.grad_x = None  # dY/dX
        self.grad_z = None  # dY/dZ
        self.slope = None   # sqrt(grad_x^2 + grad_z^2)

    @classmethod
    def circular(cls, radius_ft: float, resolution_ft: float) -> "HeightMap":
        """
        Create a flat circular green centered at (0,0) in feet.
        """
        radius_ft = float(radius_ft)
        resolution_ft = float(resolution_ft)

        x = np.arange(-radius_ft, radius_ft + resolution_ft, resolution_ft)
        z = np.arange(-radius_ft, radius_ft + resolution_ft, resolution_ft)
        X, Z = np.meshgrid(x, z)

        Y = np.zeros_like(X, dtype=float)
        mask = (X**2 + Z**2) <= radius_ft**2

        # Outside the circle -> NaN so plots & computations naturally ignore it
        Y[~mask] = np.nan

        return cls(X=X, Z=Z, Y=Y, resolution_ft=resolution_ft, mask=mask)

    def add_planar_slope(self, slope_x: float = 0.0, slope_z: float = 0.0) -> None:
        """
        Add a planar slope: Y += slope_x * X + slope_z * Z

        slope_x, slope_z are "rise per foot" (dimensionless).
        Example:
          - 2% slope in +Z direction  => slope_z = 0.02
        """
        self.Y[self.mask] = self.Y[self.mask] + slope_x * self.X[self.mask] + slope_z * self.Z[self.mask]

    def add_gaussian_bump(self, center_x_ft: float, center_z_ft: float, height_ft: float, sigma_ft: float) -> None:
        """
        Add a smooth bump/valley.
        height_ft: peak height in feet (negative makes a bowl)
        sigma_ft: spread in feet
        """
        cx = float(center_x_ft)
        cz = float(center_z_ft)
        h = float(height_ft)
        s = float(sigma_ft)

        dx = self.X - cx
        dz = self.Z - cz
        bump = h * np.exp(-(dx**2 + dz**2) / (2.0 * s**2))

        self.Y[self.mask] = self.Y[self.mask] + bump[self.mask]

    def normalize(self) -> None:
        """
        Shift heights so the minimum inside the green is 0 ft.
        """
        min_y = np.nanmin(self.Y)
        self.Y[self.mask] = self.Y[self.mask] - min_y

    def compute_gradients(self) -> None:
        """
        Compute dY/dX and dY/dZ in (ft/ft). Ignores NaNs safely.
        """
        # Fill NaNs with nearest-ish values so gradient doesn't explode at edges.
        # Simple approach: copy Y then set outside to 0 before gradient, then mask afterwards.
        Y_filled = np.where(self.mask, self.Y, 0.0)

        dZ, dX = np.gradient(Y_filled, self.resolution_ft, self.resolution_ft)

        # Mask-out gradients outside green
        dX = np.where(self.mask, dX, np.nan)
        dZ = np.where(self.mask, dZ, np.nan)

        self.grad_x = dX
        self.grad_z = dZ
        self.slope = np.sqrt(dX**2 + dZ**2)

    def _index_of(self, x_ft: float, z_ft: float) -> tuple[int, int]:
        """
        Map (x,z) to nearest grid indices (iz, ix).
        Assumes grid is centered and uniformly spaced.
        """
        # X and Z are meshgrids made from 1D arrays; grab axis vectors:
        x_axis = self.X[0, :]
        z_axis = self.Z[:, 0]

        ix = int(np.clip(np.searchsorted(x_axis, x_ft) - 1, 0, len(x_axis) - 1))
        iz = int(np.clip(np.searchsorted(z_axis, z_ft) - 1, 0, len(z_axis) - 1))
        return iz, ix

    def get_height_at(self, x_ft: float, z_ft: float) -> float:
        iz, ix = self._index_of(x_ft, z_ft)
        return float(self.Y[iz, ix])

    def get_gradient_at(self, x_ft: float, z_ft: float) -> np.ndarray:
        if self.grad_x is None or self.grad_z is None:
            raise RuntimeError("Gradients not computed yet. Call compute_gradients().")

        iz, ix = self._index_of(x_ft, z_ft)
        return np.array([self.grad_x[iz, ix], self.grad_z[iz, ix]], dtype=float)
