import json
import os
import sys
import cv2
import numpy as np
import matplotlib.pyplot as plt

from backend.maps import GreenExtentsLatLon, infer_green_size_ft, PixelToFeetTransform
from backend.tools.paths import image_path, boundary_path, config_path


class BoundaryTracer:
    """
    How it works
        Left click: add a boundary point
        Backspace: undo last point
        Enter: finish + save
    It converts clicked pixels → feet using:
    your Google N/S/E/W points → inferred width/height (ft)
    assumes the image is already North-up / East-right
    """
    def __init__(self, img_rgb, transform: PixelToFeetTransform,
                 img_path: str, out_path: str):
        self.img = img_rgb
        self.T = transform
        self.img_path = img_path
        self.out_path = out_path
        self.points_uv = []  # list of (u,v) pixels
        self.scatter = None
        self.line = None

    def redraw(self, ax):
        ax.clear()
        ax.imshow(self.img)
        ax.set_title(
            "Trace boundary: Left click=add, Backspace=undo, Enter=save/exit"
        )

        if self.points_uv:
            us = [p[0] for p in self.points_uv]
            vs = [p[1] for p in self.points_uv]
            ax.scatter(us, vs, s=25)

            # draw polyline
            ax.plot(us, vs)

            # show last point coords (feet)
            x_ft, z_ft = self.T.uv_to_xz(us[-1], vs[-1])
            ax.text(10, 20, f"Last: x={x_ft:.2f}ft, z={z_ft:.2f}ft",
                    color="white", fontsize=10,
                    bbox=dict(facecolor="black", alpha=0.5, pad=4))

        plt.draw()

    def on_click(self, event, ax):
        if event.inaxes != ax:
            return
        if event.button != 1:
            return
        u, v = float(event.xdata), float(event.ydata)
        self.points_uv.append((u, v))
        self.redraw(ax)

    def on_key(self, event, ax):
        if event.key == "backspace":
            if self.points_uv:
                self.points_uv.pop()
                self.redraw(ax)
        elif event.key == "enter":
            if len(self.points_uv) < 3:
                print("Need at least 3 points to form a polygon.")
                return
            self.save_and_exit()

    def save_and_exit(self):
        # Convert to feet coordinates
        points_xz = [self.T.uv_to_xz(u, v) for (u, v) in self.points_uv]

        payload = {
            "image_path": self.img_path,
            "image_w_px": self.T.img_w_px,
            "image_h_px": self.T.img_h_px,
            "green_width_ft": self.T.green_width_ft,
            "green_height_ft": self.T.green_height_ft,
            "points_xz_ft": [{"x": x, "z": z} for (x, z) in points_xz],
        }

        os.makedirs(os.path.dirname(self.out_path), exist_ok=True)
        with open(self.out_path, "w") as f:
            json.dump(payload, f, indent=2)

        print(f"Saved boundary JSON to: {self.out_path}")
        plt.close("all")


def main(course_name: str, hole_name: str):
    cfg_file = config_path(course_name, hole_name)
    with open(cfg_file, "r") as f:
        cfg = json.load(f)

    img_file = image_path(course_name, hole_name)
    out_file = boundary_path(course_name, hole_name)

    image_bgr = cv2.imread(img_file, cv2.IMREAD_COLOR)
    if image_bgr is None:
        raise RuntimeError(f"Could not read image at: {img_file}")

    img_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
    H, W = img_rgb.shape[:2]

    e = cfg["extents"]
    extents = GreenExtentsLatLon(
        north=(e["north"]["lat"], e["north"]["lon"]),
        south=(e["south"]["lat"], e["south"]["lon"]),
        east=(e["east"]["lat"], e["east"]["lon"]),
        west=(e["west"]["lat"], e["west"]["lon"]),
    )
    green_width_ft, green_height_ft = infer_green_size_ft(extents)

    print(f"Inferred width_ft  (E-W): {green_width_ft:.2f}")
    print(f"Inferred height_ft (N-S): {green_height_ft:.2f}")

    T = PixelToFeetTransform(
        img_w_px=W,
        img_h_px=H,
        green_width_ft=float(green_width_ft),
        green_height_ft=float(green_height_ft),
    )

    fig, ax = plt.subplots(figsize=(10, 8))
    tracer = BoundaryTracer(img_rgb, T, img_path=img_file, out_path=out_file)

    tracer.redraw(ax)

    fig.canvas.mpl_connect("button_press_event", lambda ev: tracer.on_click(ev, ax))
    fig.canvas.mpl_connect("key_press_event", lambda ev: tracer.on_key(ev, ax))

    plt.show()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python -m backend.tools.trace_boundary <course_name> <hole_name>")
        print("Example: python -m backend.tools.trace_boundary PresidioGC Hole_1")
        sys.exit(1)
    main(course_name=sys.argv[1], hole_name=sys.argv[2])
