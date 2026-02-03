from dataclasses import dataclass
from pyproj import Geod

M_TO_FT = 3.280839895

@dataclass(frozen=True)
class GreenExtentsLatLon:
    north: tuple[float, float]  # (lat, lon)
    south: tuple[float, float]
    east: tuple[float, float]
    west: tuple[float, float]

def geodesic_distance_ft(a: tuple[float, float], b: tuple[float, float]) -> float:
    """
    Geodesic distance on WGS84 ellipsoid.
    a, b are (lat, lon).
    Returns feet.
    """
    geod = Geod(ellps="WGS84")
    lat1, lon1 = a
    lat2, lon2 = b
    _, _, dist_m = geod.inv(lon1, lat1, lon2, lat2)  # (az12, az21, dist_m)
    return dist_m * M_TO_FT

def infer_green_size_ft(extents: GreenExtentsLatLon) -> tuple[float, float]:
    """
    Returns (green_width_ft, green_height_ft)
    """
    height_ft = geodesic_distance_ft(extents.north, extents.south)
    width_ft  = geodesic_distance_ft(extents.east, extents.west)
    return width_ft, height_ft
