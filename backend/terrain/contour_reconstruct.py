import numpy as np
from shapely.geometry import Point, Polygon
from scipy.interpolate import RBFInterpolator


def sample_polyline(points_xz, step_ft: float = 1.0):
    """
    Densify a polyline by sampling roughly every step_ft along segments.
    points_xz: list of (x,z)
    Returns list of sampled (x,z)
    """
    pts = []
    for i in range(len(points_xz) - 1):
        x1, z1 = points_xz[i]
        x2, z2 = points_xz[i + 1]
        dx, dz = x2 - x1, z2 - z1
        dist = float(np.hypot(dx, dz))
        n = max(1, int(dist / step_ft))
        for t in np.linspace(0, 1, n, endpoint=False):
            pts.append((x1 + t * dx, z1 + t * dz))
    pts.append(points_xz[-1])
    return pts


def reconstruct_heightfield_from_contours(
    boundary_poly: Polygon,
    contours: list[dict],
    grid_x: np.ndarray,
    grid_z: np.ndarray,
    sample_step_ft: float = 1.0,
    smooth: float = 0.1,
):
    """
    boundary_poly: shapely Polygon in (x,z) feet
    contours: list of dicts { "height_ft": float, "points_xz": [(x,z), ...] }
    grid_x, grid_z: meshgrid arrays (same shape)
    Returns:
      Y_ft (same shape), mask_inside (bool same shape)
    """
    # 1) Build sample constraints from contours
    xs, zs, hs = [], [], []
    for c in contours:
        h = float(c["height_ft"])
        pts = sample_polyline(c["points_xz"], step_ft=sample_step_ft)
        for (x, z) in pts:
            xs.append(x)
            zs.append(z)
            hs.append(h)

    if len(xs) < 10:
        raise RuntimeError("Not enough contour samples. Trace more/longer contours.")

    Xs = np.column_stack([np.array(xs), np.array(zs)])
    ys = np.array(hs)

    # 2) Interpolator (thin-plate spline style)
    # smooth: larger -> smoother surface, less exact contour fit
    rbf = RBFInterpolator(Xs, ys, kernel="thin_plate_spline", smoothing=smooth)

    # 3) Evaluate on grid
    pts_grid = np.column_stack([grid_x.ravel(), grid_z.ravel()])
    Y = rbf(pts_grid).reshape(grid_x.shape)

    # 4) Mask outside boundary
    inside = np.vectorize(lambda x, z: boundary_poly.contains(Point(x, z)))(grid_x, grid_z)
    Y[~inside] = np.nan

    # 5) Normalize so min inside is 0
    Y = Y - np.nanmin(Y)

    return Y, inside
