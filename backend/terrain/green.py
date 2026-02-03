class Green:
    """
    Green domain object.
    Holds a HeightMap (feet) and hole locations (feet).
    """

    def __init__(self, heightmap):
        self.heightmap = heightmap
        self.holes = []

    def add_hole(self, hole_id: str, x_ft: float, z_ft: float) -> None:
        self.holes.append({"id": hole_id, "x": float(x_ft), "z": float(z_ft)})

    # Convenience wrappers
    def get_height_at(self, x_ft: float, z_ft: float) -> float:
        return self.heightmap.get_height_at(x_ft, z_ft)

    def get_gradient_at(self, x_ft: float, z_ft: float):
        return self.heightmap.get_gradient_at(x_ft, z_ft)
