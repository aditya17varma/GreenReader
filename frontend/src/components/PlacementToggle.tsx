import { Button } from "@/components/ui/button";
import type { PlacementMode } from "@/lib/types";

interface PlacementToggleProps {
  mode: PlacementMode;
  onChange: (mode: PlacementMode) => void;
}

export function PlacementToggle({ mode, onChange }: PlacementToggleProps) {
  return (
    <div className="flex gap-2">
      <Button
        variant={mode === "flag" ? "default" : "outline"}
        size="sm"
        onClick={() => onChange("flag")}
      >
        Place Flag
      </Button>
      <Button
        variant={mode === "ball" ? "default" : "outline"}
        size="sm"
        onClick={() => onChange("ball")}
      >
        Place Ball
      </Button>
    </div>
  );
}
