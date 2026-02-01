import { useState } from "react";
import { CourseSelector } from "@/components/CourseSelector";
import { GreenCanvas } from "@/components/GreenCanvas";
import { PlacementToggle } from "@/components/PlacementToggle";
import { BestLineResult } from "@/components/BestLineResult";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Slider } from "@/components/ui/slider";
import { getHole, computeBestLine } from "@/lib/api";
import type {
  HoleDetail,
  PositionFt,
  PlacementMode,
  BestLineResult as BestLineResultType,
} from "@/lib/types";

export default function App() {
  const [holeData, setHoleData] = useState<HoleDetail | null>(null);
  const [placementMode, setPlacementMode] = useState<PlacementMode>("flag");
  const [flagPos, setFlagPos] = useState<PositionFt | null>(null);
  const [ballPos, setBallPos] = useState<PositionFt | null>(null);
  const [stimpFt, setStimpFt] = useState(10);
  const [bestLine, setBestLine] = useState<BestLineResultType | null>(null);
  const [computing, setComputing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleHoleSelect(courseId: string, holeNum: number) {
    setFlagPos(null);
    setBallPos(null);
    setBestLine(null);
    setError(null);
    try {
      const data = await getHole(courseId, holeNum);
      setHoleData(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load hole");
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

  async function handleCompute() {
    if (!holeData || !flagPos || !ballPos) return;
    setComputing(true);
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
        }
      );
      setBestLine(result);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Compute failed");
    } finally {
      setComputing(false);
    }
  }

  const imageUrl = holeData?.sourceUrls?.["image.png"];
  const canCompute = !!flagPos && !!ballPos && !!holeData && !computing;

  return (
    <div className="flex min-h-screen bg-background text-foreground">
      {/* Sidebar */}
      <aside className="w-72 shrink-0 border-r p-4 flex flex-col gap-6 overflow-y-auto">
        <h1 className="text-lg font-semibold">GreenReader</h1>

        <CourseSelector onHoleSelect={handleHoleSelect} />

        {holeData && (
          <>
            <div className="flex flex-col gap-2">
              <Label>Placement Mode</Label>
              <PlacementToggle
                mode={placementMode}
                onChange={setPlacementMode}
              />
            </div>

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

            <Button
              onClick={handleCompute}
              disabled={!canCompute}
            >
              {computing ? "Computing..." : "Compute Best Line"}
            </Button>

            {bestLine && <BestLineResult result={bestLine} />}
          </>
        )}

        {error && <p className="text-sm text-destructive">{error}</p>}
      </aside>

      {/* Main area */}
      <main className="flex-1 flex items-center justify-center p-4 overflow-auto">
        {imageUrl && holeData ? (
          <GreenCanvas
            imageUrl={imageUrl}
            greenWidthFt={holeData.greenWidthFt}
            greenHeightFt={holeData.greenHeightFt}
            placementMode={placementMode}
            ballPos={ballPos}
            flagPos={flagPos}
            bestLine={bestLine}
            onPlace={handlePlace}
          />
        ) : (
          <p className="text-muted-foreground">
            Select a course and hole to begin
          </p>
        )}
      </main>
    </div>
  );
}
