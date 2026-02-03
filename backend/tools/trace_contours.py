import json
import os
import sys
import cv2
import numpy as np
import matplotlib.pyplot as plt

from backend.maps import GreenExtentsLatLon, infer_green_size_ft, PixelToFeetTransform
from backend.tools.paths import contour_path, contours_path, config_path


class ContourTracer:
    """
    Controls
    Left click: add point to current contour
    Backspace: undo last point
    n: finish current contour, increment level k (you can also go backwards)
    p: finish current contour, decrement level k
    c: clear current contour points (does not delete saved contours)
    s: save contours to JSON
    q: quit
    It stores everything in green-local feet, using the same scaling we've already established from extents.
    """
    def __init__(self, img_rgb, T: PixelToFeetTransform,
                 img_path: str, out_path: str, contour_interval_ft: float):
        self.img = img_rgb
        self.T = T
        self.img_path = img_path
        self.out_path = out_path
        self.contour_interval_ft = contour_interval_ft

        self.k = 0  # current contour level index
        self.current_uv = []  # points for current contour
        self.contours = []  # list of dicts: {"k": int, "points_uv": [...]}

    def redraw(self, ax):
        ax.clear()
        ax.imshow(self.img)
        ax.set_title(
            f"Trace contours | k={self.k} (height={self.k*self.contour_interval_ft:.2f}ft) | "
            "LClick=add, Backspace=undo, n=next(k+1), p=prev(k-1), c=clear, s=save, q=quit"
        )

        # Draw saved contours
        for c in self.contours:
            pts = c["points_uv"]
            if len(pts) >= 2:
                us = [p[0] for p in pts]
                vs = [p[1] for p in pts]
                ax.plot(us, vs, linewidth=1.5)
                ax.text(us[0], vs[0], f'k={c["k"]}', color="yellow",
                        fontsize=9, bbox=dict(facecolor="black", alpha=0.4, pad=2))

        # Draw current contour
        if self.current_uv:
            us = [p[0] for p in self.current_uv]
            vs = [p[1] for p in self.current_uv]
            ax.scatter(us, vs, s=18)
            ax.plot(us, vs, linewidth=2.5)

        plt.draw()

    def finish_current(self):
        if len(self.current_uv) < 2:
            self.current_uv = []
            return

        self.contours.append({
            "k": int(self.k),
            "points_uv": list(self.current_uv),
        })
        self.current_uv = []

    def on_click(self, event, ax):
        if event.inaxes != ax:
            return
        if event.button != 1:
            return
        u, v = float(event.xdata), float(event.ydata)
        self.current_uv.append((u, v))
        self.redraw(ax)

    def on_key(self, event, ax):
        key = event.key

        if key == "backspace":
            if self.current_uv:
                self.current_uv.pop()
                self.redraw(ax)
            return

        if key == "c":
            self.current_uv = []
            self.redraw(ax)
            return

        if key == "n":
            self.finish_current()
            self.k += 1
            self.redraw(ax)
            return

        if key == "p":
            self.finish_current()
            self.k -= 1
            self.redraw(ax)
            return

        if key == "s":
            self.finish_current()
            self.save()
            return

        if key == "q":
            plt.close("all")
            return

    def save(self):
        # Convert UV -> XZ feet for each contour
        contours_xz = []
        for c in self.contours:
            pts_xz = [self.T.uv_to_xz(u, v) for (u, v) in c["points_uv"]]
            contours_xz.append({
                "k": int(c["k"]),
                "height_ft": float(c["k"] * self.contour_interval_ft),
                "points_xz_ft": [{"x": float(x), "z": float(z)} for (x, z) in pts_xz],
            })

        payload = {
            "image_path": self.img_path,
            "image_w_px": self.T.img_w_px,
            "image_h_px": self.T.img_h_px,
            "green_width_ft": self.T.green_width_ft,
            "green_height_ft": self.T.green_height_ft,
            "contour_interval_ft": self.contour_interval_ft,
            "contours": contours_xz,
        }

        os.makedirs(os.path.dirname(self.out_path), exist_ok=True)
        with open(self.out_path, "w") as f:
            json.dump(payload, f, indent=2)

        print(f"Saved contours to: {self.out_path} (contours={len(contours_xz)})")


def main(course_name: str, hole_name: str):
    cfg_file = config_path(course_name, hole_name)
    with open(cfg_file, "r") as f:
        cfg = json.load(f)

    img_file = contour_path(course_name, hole_name)
    out_file = contours_path(course_name, hole_name)
    contour_interval_ft = cfg.get("contour_interval_ft", 0.25)

    # Load image
    image_bgr = cv2.imread(img_file, cv2.IMREAD_COLOR)
    if image_bgr is None:
        raise RuntimeError(f"Could not read image: {img_file}")
    img_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
    H, Wpx = img_rgb.shape[:2]

    # Infer scale from config extents
    e = cfg["extents"]
    extents = GreenExtentsLatLon(
        north=(e["north"]["lat"], e["north"]["lon"]),
        south=(e["south"]["lat"], e["south"]["lon"]),
        east=(e["east"]["lat"], e["east"]["lon"]),
        west=(e["west"]["lat"], e["west"]["lon"]),
    )
    green_width_ft, green_height_ft = infer_green_size_ft(extents)

    T = PixelToFeetTransform(
        img_w_px=Wpx,
        img_h_px=H,
        green_width_ft=float(green_width_ft),
        green_height_ft=float(green_height_ft),
    )

    fig, ax = plt.subplots(figsize=(10, 8))
    tracer = ContourTracer(
        img_rgb, T,
        img_path=img_file,
        out_path=out_file,
        contour_interval_ft=contour_interval_ft,
    )
    tracer.redraw(ax)

    fig.canvas.mpl_connect("button_press_event", lambda ev: tracer.on_click(ev, ax))
    fig.canvas.mpl_connect("key_press_event", lambda ev: tracer.on_key(ev, ax))

    plt.show()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python -m backend.tools.trace_contours <course_name> <hole_name>")
        print("Example: python -m backend.tools.trace_contours PresidioGC Hole_1")
        sys.exit(1)
    main(course_name=sys.argv[1], hole_name=sys.argv[2])
