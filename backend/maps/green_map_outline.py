import numpy as np
import cv2


def extract_green_mask_from_boundary(image_bgr: np.ndarray) -> np.ndarray:
    """
    Robustly extract inside-green mask using ONLY the boundary.

    Steps:
      1) Threshold to find dark pixels (boundary line).
      2) Morphologically close gaps in the boundary.
      3) Flood-fill from the image border to mark "outside".
      4) Inside-green = NOT outside AND NOT boundary.

    This is robust to white patches inside the green (0% slope areas).
    """
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)

    # 1) Threshold for dark boundary pixels.
    # Tune 'thresh' if your boundary isn't detected strongly.
    thresh = 70
    boundary = (gray < thresh).astype(np.uint8) * 255

    # 2) Close small gaps in boundary so floodfill doesn't leak in.
    kernel = np.ones((7, 7), np.uint8)
    boundary_closed = cv2.morphologyEx(boundary, cv2.MORPH_CLOSE, kernel, iterations=2)

    # Optional: slightly dilate boundary to ensure it's watertight
    boundary_closed = cv2.dilate(boundary_closed, kernel, iterations=1)

    # 3) Flood fill "outside" starting from the image border.
    # Create an image where boundary pixels are "walls" (255), others are 0.
    walls = boundary_closed.copy()

    h, w = walls.shape
    flood = walls.copy()

    # Flood fill expects a mask that's 2 pixels larger than the image.
    ff_mask = np.zeros((h + 2, w + 2), dtype=np.uint8)

    # Flood fill from top-left corner (assumed outside).
    # If your top-left could ever be inside, pick another corner or do multiple.
    cv2.floodFill(flood, ff_mask, seedPoint=(0, 0), newVal=128)

    # Pixels marked 128 are reachable from outside without crossing boundary.
    outside = (flood == 128)

    # 4) Inside is everything that's not outside and not boundary walls.
    inside = (~outside) & (walls == 0)

    return inside
