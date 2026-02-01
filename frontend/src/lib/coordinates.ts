/**
 * Convert a pixel position on the displayed image to local feet coordinates.
 *
 * Image origin: top-left, y increases downward.
 * Feet origin: image center, x increases right, z increases up.
 */
export function pixelToFeet(
  px: number,
  py: number,
  displayW: number,
  displayH: number,
  greenWFt: number,
  greenHFt: number
): { xFt: number; zFt: number } {
  const xFt = (px / displayW - 0.5) * greenWFt;
  const zFt = (0.5 - py / displayH) * greenHFt;
  return { xFt, zFt };
}

/**
 * Convert local feet coordinates to a pixel position on the displayed image.
 */
export function feetToPixel(
  xFt: number,
  zFt: number,
  displayW: number,
  displayH: number,
  greenWFt: number,
  greenHFt: number
): { px: number; py: number } {
  const px = (xFt / greenWFt + 0.5) * displayW;
  const py = (0.5 - zFt / greenHFt) * displayH;
  return { px, py };
}
