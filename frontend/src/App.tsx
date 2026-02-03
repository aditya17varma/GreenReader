import { useState, useEffect, useRef, useCallback, lazy, Suspense } from "react";
import { CourseSelector } from "@/components/CourseSelector";
import { GreenCanvas } from "@/components/GreenCanvas";
import { PlacementToggle } from "@/components/PlacementToggle";
import { BestLineResult } from "@/components/BestLineResult";
import { ComputeProgress } from "@/components/ComputeProgress";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Slider } from "@/components/ui/slider";
import { getHole, computeBestLine } from "@/lib/api";
import type { ComputeStatus } from "@/lib/api";
import type {
  HoleDetail,
  PositionFt,
  PlacementMode,
  BestLineResult as BestLineResultType,
} from "@/lib/types";

const LazyUnityViewer = lazy(() =>
  import("@/components/UnityViewer").then((m) => ({ default: m.UnityViewer }))
);

export default function App() {
  const [holeData, setHoleData] = useState<HoleDetail | null>(null);
  const [placementMode, setPlacementMode] = useState<PlacementMode>("flag");
  const [flagPos, setFlagPos] = useState<PositionFt | null>(null);
  const [ballPos, setBallPos] = useState<PositionFt | null>(null);
  const [stimpFt, setStimpFt] = useState(10);
  const [bestLine, setBestLine] = useState<BestLineResultType | null>(null);
  const [computing, setComputing] = useState(false);
  const [computeStatus, setComputeStatus] = useState<ComputeStatus | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [imageLoading, setImageLoading] = useState(false);
  const [show3D, setShow3D] = useState(false);
  const [hasOpened3D, setHasOpened3D] = useState(false);
  const computeRef = useRef(false);

  async function handleHoleSelect(courseId: string, holeNum: number) {
    setFlagPos(null);
    setBallPos(null);
    setBestLine(null);
    setError(null);
    setImageLoading(true);
    try {
      const data = await getHole(courseId, holeNum);
      setHoleData(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load hole");
      setImageLoading(false);
    }
  }

  function handlePlace(pos: PositionFt) {
    if (placementMode === "flag") {
      setFlagPos(pos);
    } else {
      setBallPos(pos);
    }
    setBestLine(null);
  }

  function handleReset() {
    setFlagPos(null);
    setBallPos(null);
    setBestLine(null);
    setError(null);
    setComputeStatus(null);
  }

  const handleCompute = useCallback(async () => {
    if (!holeData || !flagPos || !ballPos || computeRef.current) return;
    computeRef.current = true;
    setComputing(true);
    setComputeStatus(null);
    setError(null);
    try {
      const result = await computeBestLine(
        holeData.courseId,
        holeData.holeNum,
        {
          ballXFt: ballPos.xFt,
          ballZFt: ballPos.zFt,
          holeXFt: flagPos.xFt,
          holeZFt: flagPos.zFt,
          stimpFt,
        },
        setComputeStatus
      );
      setBestLine(result);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Compute failed");
    } finally {
      setComputing(false);
      setComputeStatus(null);
      computeRef.current = false;
    }
  }, [holeData, flagPos, ballPos, stimpFt]);

  // Keyboard shortcuts
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;

      switch (e.key.toLowerCase()) {
        case "f":
          if (holeData) setPlacementMode("flag");
          break;
        case "b":
          if (holeData) setPlacementMode("ball");
          break;
        case "enter":
          if (holeData && flagPos && ballPos && !computing) handleCompute();
          break;
        case "escape":
          if (holeData) handleReset();
          break;
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [holeData, flagPos, ballPos, computing, handleCompute]);

  const imageUrl = holeData?.sourceUrls?.["image.png"];
  const canCompute = !!flagPos && !!ballPos && !!holeData && !computing;
  const puttDistanceFt =
    flagPos && ballPos
      ? Math.hypot(flagPos.xFt - ballPos.xFt, flagPos.zFt - ballPos.zFt)
      : null;

  return (
    <div className="flex min-h-screen bg-background text-foreground">
      {/* Mobile toggle */}
      <button
        className="fixed top-3 left-3 z-50 rounded-md border bg-background p-2 md:hidden"
        onClick={() => setSidebarOpen((v) => !v)}
        aria-label="Toggle sidebar"
      >
        <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2">
          <path d="M3 5h14M3 10h14M3 15h14" />
        </svg>
      </button>

      {/* Sidebar */}
      <aside
        className={`
          fixed inset-y-0 left-0 z-40 w-72 border-r bg-background p-4 flex flex-col gap-6 overflow-y-auto
          transition-transform duration-200 ease-in-out
          md:relative md:translate-x-0 md:shrink-0
          ${sidebarOpen ? "translate-x-0" : "-translate-x-full"}
        `}
      >
        <h1 className="text-lg font-semibold">GreenReader</h1>

        <CourseSelector onHoleSelect={handleHoleSelect} />

        {holeData && (
          <>
            <div className="flex flex-col gap-2">
              <Label>
                Placement Mode
                <span className="ml-2 text-xs text-muted-foreground font-normal">
                  (F / B)
                </span>
              </Label>
              <PlacementToggle
                mode={placementMode}
                onChange={setPlacementMode}
              />
            </div>

            <div className="flex flex-col gap-1">
              {flagPos && (
                <p className="text-xs text-muted-foreground">
                  Flag: ({flagPos.xFt.toFixed(1)}, {flagPos.zFt.toFixed(1)}) ft
                </p>
              )}
              {ballPos && (
                <p className="text-xs text-muted-foreground">
                  Ball: ({ballPos.xFt.toFixed(1)}, {ballPos.zFt.toFixed(1)}) ft
                </p>
              )}
              {puttDistanceFt !== null && (
                <p className="text-xs font-medium text-foreground">
                  Distance: {puttDistanceFt.toFixed(1)} ft
                </p>
              )}
            </div>

            <div className="flex flex-col gap-2">
              <Label>Stimp: {stimpFt.toFixed(1)} ft</Label>
              <Slider
                min={6}
                max={15}
                step={0.5}
                value={[stimpFt]}
                onValueChange={([v]) => setStimpFt(v)}
              />
            </div>

            <div className="flex gap-2">
              <Button
                className="flex-1"
                onClick={handleCompute}
                disabled={!canCompute}
              >
                {computing ? "Computing..." : "Compute Best Line"}
              </Button>
              <Button
                variant="outline"
                size="icon"
                onClick={handleReset}
                title="Reset markers (Esc)"
              >
                <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M2 2v5h5" />
                  <path d="M2.5 7A6 6 0 1 1 3 10" />
                </svg>
              </Button>
            </div>

            {computing && computeStatus && (
              <ComputeProgress status={computeStatus} />
            )}

            {bestLine && (
              <>
                <BestLineResult result={bestLine} />
                <Button
                  variant="outline"
                  className="w-full"
                  onClick={() => {
                    setHasOpened3D(true);
                    setShow3D(true);
                  }}
                >
                  View 3D Simulation
                </Button>
              </>
            )}
          </>
        )}

        {error && <p className="text-sm text-destructive">{error}</p>}
      </aside>

      {/* Backdrop for mobile sidebar */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 z-30 bg-black/40 md:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Main area */}
      <main className="flex-1 flex items-center justify-center p-4 overflow-auto">
        {imageUrl && holeData ? (
          <div className="relative w-full h-full">
            {imageLoading && (
              <div className="absolute inset-0 flex items-center justify-center bg-muted rounded-lg animate-pulse z-20">
                <p className="text-muted-foreground text-sm">Loading green...</p>
              </div>
            )}

            {!show3D && (
              <GreenCanvas
                imageUrl={imageUrl}
                greenWidthFt={holeData.greenWidthFt}
                greenHeightFt={holeData.greenHeightFt}
                placementMode={placementMode}
                ballPos={ballPos}
                flagPos={flagPos}
                bestLine={bestLine}
                onPlace={handlePlace}
                onImageLoad={() => setImageLoading(false)}
              />
            )}

            {hasOpened3D && holeData && ballPos && flagPos && bestLine && (
              <div
                className={[
                  "absolute inset-0",
                  show3D ? "opacity-100 pointer-events-auto" : "opacity-0 pointer-events-none",
                ].join(" ")}
              >
                <Suspense
                  fallback={
                    <div className="flex items-center gap-2 text-sm text-muted-foreground">
                      <span className="h-2 w-2 rounded-full bg-primary animate-pulse" />
                      Loading 3D viewer…
                    </div>
                  }
                >
                  <LazyUnityViewer
                    holeData={holeData}
                    ballPos={ballPos}
                    flagPos={flagPos}
                    bestLine={bestLine}
                    onClose={() => setShow3D(false)}
                  />
                </Suspense>
              </div>
            )}
          </div>
        ) : (
          <p className="text-muted-foreground">
            Select a course and hole to begin
          </p>
        )}
      </main>
    </div>
  );
}
