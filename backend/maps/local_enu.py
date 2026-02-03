import math
from dataclasses import dataclass
from pyproj import Geod

M_TO_FT = 3.280839895

@dataclass(frozen=True)
class RefFrame:
    lat0: float
    lon0: float

def ref_from_extents(north, south, east, west) -> RefFrame:
    # each arg is (lat, lon)
    lat0 = (north[0] + south[0] + east[0] + west[0]) / 4.0
    lon0 = (north[1] + south[1] + east[1] + west[1]) / 4.0
    return RefFrame(lat0=lat0, lon0=lon0)

def latlon_to_xz_ft(ref: RefFrame, lat: float, lon: float) -> tuple[float, float]:
    """
    Returns (x_ft, z_ft) where:
      x = east (+)
      z = north (+)
    """
    geod = Geod(ellps="WGS84")
    az12_deg, _, dist_m = geod.inv(ref.lon0, ref.lat0, lon, lat)
    az = math.radians(az12_deg)

    east_m = dist_m * math.sin(az)
    north_m = dist_m * math.cos(az)

    return east_m * M_TO_FT, north_m * M_TO_FT
