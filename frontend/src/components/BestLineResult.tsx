import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import type { BestLineResult as BestLineResultType } from "@/lib/types";

interface BestLineResultProps {
  result: BestLineResultType;
}

export function BestLineResult({ result }: BestLineResultProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Best Line</CardTitle>
      </CardHeader>
      <CardContent>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
          <dt className="text-muted-foreground">Aim Offset</dt>
          <dd>{result.aimOffsetDeg.toFixed(1)}&deg;</dd>

          <dt className="text-muted-foreground">Speed</dt>
          <dd>{result.speedFps.toFixed(2)} ft/s</dd>

          <dt className="text-muted-foreground">Holed</dt>
          <dd>{result.holed ? "Yes" : "No"}</dd>

          {!result.holed && (
            <>
              <dt className="text-muted-foreground">Miss Distance</dt>
              <dd>{result.missFt.toFixed(2)} ft</dd>
            </>
          )}

          <dt className="text-muted-foreground">Roll Time</dt>
          <dd>{result.tEndS.toFixed(2)} s</dd>

          <dt className="text-muted-foreground">Stimp</dt>
          <dd>{result.stimpFt.toFixed(1)} ft</dd>
        </dl>
      </CardContent>
    </Card>
  );
}
