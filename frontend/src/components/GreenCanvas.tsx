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

    // Draw best line path
    if (bestLine && bestLine.pathXFt.length > 1) {
      ctx.beginPath();
      for (let i = 0; i < bestLine.pathXFt.length; i++) {
        const { px, py } = feetToPixel(
          bestLine.pathXFt[i],
          bestLine.pathZFt[i],
          w,
          h,
          greenWidthFt,
          greenHeightFt
        );
        if (i === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      ctx.strokeStyle = "#facc15";
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    // Draw flag marker
    if (flagPos) {
      const { px, py } = feetToPixel(
        flagPos.xFt,
        flagPos.zFt,
        w,
        h,
        greenWidthFt,
        greenHeightFt
      );
      drawFlag(ctx, px, py);
    }

    // Draw ball marker
    if (ballPos) {
      const { px, py } = feetToPixel(
        ballPos.xFt,
        ballPos.zFt,
        w,
        h,
        greenWidthFt,
        greenHeightFt
      );
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
        onLoad={draw}
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
