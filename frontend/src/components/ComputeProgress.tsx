import { useState, useEffect } from "react";
import type { ComputeStatus } from "@/lib/api";

const STATUS_LABELS: Record<ComputeStatus, string> = {
  submitting: "Submitting job...",
  queued: "Queued — waiting for compute...",
  running: "Running simulation...",
  loading: "Loading result...",
};

interface ComputeProgressProps {
  status: ComputeStatus;
}

export function ComputeProgress({ status }: ComputeProgressProps) {
  const [elapsed, setElapsed] = useState(0);

  useEffect(() => {
    setElapsed(0);
    const t = setInterval(() => setElapsed((s) => s + 1), 1000);
    return () => clearInterval(t);
  }, []);

  return (
    <div className="flex flex-col gap-1.5 rounded-md border p-3 bg-muted/50">
      <div className="flex items-center gap-2">
        <span className="h-2 w-2 rounded-full bg-primary animate-pulse" />
        <span className="text-sm">{STATUS_LABELS[status]}</span>
      </div>
      <p className="text-xs text-muted-foreground pl-4">
        Elapsed: {elapsed}s
      </p>
    </div>
  );
}
