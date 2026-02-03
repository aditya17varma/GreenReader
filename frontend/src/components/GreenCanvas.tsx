import { useRef, useEffect, useCallback } from "react";
import { pixelToFeet, feetToPixel } from "@/lib/coordinates";
import type {
  PositionFt,
  PlacementMode,
  BestLineResult,
} from "@/lib/types";

interface GreenCanvasProps {
  imageUrl: string;
  greenWidthFt: number;
  greenHeightFt: number;
  placementMode: PlacementMode;
  ballPos: PositionFt | null;
  flagPos: PositionFt | null;
  bestLine: BestLineResult | null;
  onPlace: (pos: PositionFt) => void;
  onImageLoad?: () => void;
}

export function GreenCanvas({
  imageUrl,
  greenWidthFt,
  greenHeightFt,
  placementMode,
  ballPos,
  flagPos,
  bestLine,
  onPlace,
  onImageLoad,
}: GreenCanvasProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const imgRef = useRef<HTMLImageElement>(null);

  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    const img = imgRef.current;
    if (!canvas || !img) return;

    const w = img.clientWidth;
    const h = img.clientHeight;
    canvas.width = w;
    canvas.height = h;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.clearRect(0, 0, w, h);

    // Dim the background image so markers and path pop
    ctx.fillStyle = "rgba(0, 0, 0, 0.4)";
    ctx.fillRect(0, 0, w, h);

    const toPixel = (xFt: number, zFt: number) =>
      feetToPixel(xFt, zFt, w, h, greenWidthFt, greenHeightFt);

    // Draw hole cup at flag position
    if (flagPos) {
      const { px, py } = toPixel(flagPos.xFt, flagPos.zFt);
      drawHoleCup(ctx, px, py);
    }

    // Draw best line path
    if (bestLine && bestLine.pathXFt.length > 1) {
      drawPath(ctx, bestLine, w, h, greenWidthFt, greenHeightFt);
    }

    // Draw flag marker
    if (flagPos) {
      const { px, py } = toPixel(flagPos.xFt, flagPos.zFt);
      drawFlag(ctx, px, py);
    }

    // Draw ball marker
    if (ballPos) {
      const { px, py } = toPixel(ballPos.xFt, ballPos.zFt);
      drawBall(ctx, px, py);
    }
  }, [ballPos, flagPos, bestLine, greenWidthFt, greenHeightFt]);

  useEffect(() => {
    draw();
  }, [draw]);

  // Redraw on window resize
  useEffect(() => {
    const handleResize = () => draw();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, [draw]);

  function handleImageLoad() {
    draw();
    onImageLoad?.();
  }

  function handleClick(e: React.MouseEvent<HTMLCanvasElement>) {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const offsetX = e.clientX - rect.left;
    const offsetY = e.clientY - rect.top;
    const pos = pixelToFeet(
      offsetX,
      offsetY,
      canvas.width,
      canvas.height,
      greenWidthFt,
      greenHeightFt
    );
    onPlace(pos);
  }

  return (
    <div ref={containerRef} className="relative inline-block">
      <img
        ref={imgRef}
        src={imageUrl}
        alt="Green"
        className="block max-w-full h-auto"
        crossOrigin="anonymous"
        onLoad={handleImageLoad}
      />
      <canvas
        ref={canvasRef}
        onClick={handleClick}
        className="absolute top-0 left-0 w-full h-full"
        style={{ cursor: placementMode === "flag" ? "crosshair" : "pointer" }}
      />
    </div>
  );
}

function drawPath(
  ctx: CanvasRenderingContext2D,
  bestLine: BestLineResult,
  w: number,
  h: number,
  greenWidthFt: number,
  greenHeightFt: number
) {
  const { px, py } = feetToPixel(
    bestLine.pathXFt[0], bestLine.pathZFt[0], w, h, greenWidthFt, greenHeightFt
  );
  ctx.beginPath();
  ctx.moveTo(px, py);
  for (let i = 1; i < bestLine.pathXFt.length; i++) {
    const { px: x, py: y } = feetToPixel(
      bestLine.pathXFt[i], bestLine.pathZFt[i], w, h, greenWidthFt, greenHeightFt
    );
    ctx.lineTo(x, y);
  }
  ctx.strokeStyle = "#3b82f6";
  ctx.lineWidth = 5;
  ctx.stroke();
}

function drawHoleCup(ctx: CanvasRenderingContext2D, x: number, y: number) {
  ctx.beginPath();
  ctx.arc(x, y, 6, 0, Math.PI * 2);
  ctx.fillStyle = "rgba(0, 0, 0, 0.5)";
  ctx.fill();
  ctx.strokeStyle = "rgba(255, 255, 255, 0.4)";
  ctx.lineWidth = 1;
  ctx.stroke();
}

function drawFlag(ctx: CanvasRenderingContext2D, x: number, y: number) {
  // Pole
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.lineTo(x, y - 24);
  ctx.strokeStyle = "#ffffff";
  ctx.lineWidth = 2;
  ctx.stroke();

  // Flag triangle
  ctx.beginPath();
  ctx.moveTo(x, y - 24);
  ctx.lineTo(x + 12, y - 18);
  ctx.lineTo(x, y - 12);
  ctx.closePath();
  ctx.fillStyle = "#ef4444";
  ctx.fill();

  // Base circle
  ctx.beginPath();
  ctx.arc(x, y, 3, 0, Math.PI * 2);
  ctx.fillStyle = "#ffffff";
  ctx.fill();
}

function drawBall(ctx: CanvasRenderingContext2D, x: number, y: number) {
  ctx.beginPath();
  ctx.arc(x, y, 5, 0, Math.PI * 2);
  ctx.fillStyle = "#ffffff";
  ctx.fill();
  ctx.strokeStyle = "#1e293b";
  ctx.lineWidth = 1.5;
  ctx.stroke();
}
