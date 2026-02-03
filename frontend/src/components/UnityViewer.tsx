import { useEffect, useCallback } from "react";
import { useUnityContext, Unity } from "react-unity-webgl";
import type { BestLineResult, HoleDetail, PositionFt } from "@/lib/types";

/**
 * Unity WebGL build paths — update these to match where you host
 * your Unity WebGL build output (Build folder contents).
 *
 * Expected structure under public/unity/:
 *   Build.loader.js
 *   Build.data.br       (or .gz / uncompressed)
 *   Build.framework.js.br
 *   Build.wasm.br
 */
const UNITY_BUILD_BASE = "/unity/WebGLBuild/Build";

interface UnityViewerProps {
  holeData: HoleDetail;
  ballPos: PositionFt;
  flagPos: PositionFt;
  bestLine: BestLineResult;
  onClose: () => void;
}

export function UnityViewer({
  holeData,
  ballPos,
  flagPos,
  bestLine,
  onClose,
}: UnityViewerProps) {
  const { unityProvider, sendMessage, isLoaded, loadingProgression } =
    useUnityContext({
      loaderUrl: `${UNITY_BUILD_BASE}/WebGLBuild.loader.js`,
      dataUrl: `${UNITY_BUILD_BASE}/WebGLBuild.data.br`,
      frameworkUrl: `${UNITY_BUILD_BASE}/WebGLBuild.framework.js.br`,
      codeUrl: `${UNITY_BUILD_BASE}/WebGLBuild.wasm.br`,
    });

  const loadScene = useCallback(() => {
    if (!isLoaded) return;

    // const heightfieldUrl = holeData.processedUrls?.["heightfield.bin"]
    //   ?? holeData.sourceUrls?.["heightfield.bin"]
    //   ?? "";

    const payload = JSON.stringify({
      heightfieldUrl: holeData.processedUrls?.["heightfield.bin"] ?? "",
      heightfieldMetaUrl: holeData.processedUrls?.["heightfield.json"] ?? "",
      greenWidthFt: holeData.greenWidthFt,
      greenHeightFt: holeData.greenHeightFt,
      ballXFt: ballPos.xFt,
      ballZFt: ballPos.zFt,
      holeXFt: flagPos.xFt,
      holeZFt: flagPos.zFt,
      pathXFt: bestLine.pathXFt,
      pathZFt: bestLine.pathZFt,
      pathYFt: bestLine.pathYFt,
      stimpFt: bestLine.stimpFt,
      speedFps: bestLine.speedFps,
    });

    // Send data to the "GreenManager" GameObject's "LoadGreen" method.
    // Adjust the GameObject name and method to match your Unity C# script.
    sendMessage("GreenManager", "LoadGreen", payload);
  }, [isLoaded, holeData, ballPos, flagPos, bestLine, sendMessage]);

  useEffect(() => {
    loadScene();
  }, [loadScene]);

  // Close on Escape
  useEffect(() => {
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [onClose]);

  return (
    <div className="flex flex-col items-center gap-3 w-full h-full">
      {!isLoaded && (
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <span className="h-2 w-2 rounded-full bg-primary animate-pulse" />
          Loading 3D viewer… {Math.round(loadingProgression * 100)}%
        </div>
      )}
      <div className="relative w-full flex-1 min-h-0">
        <Unity
          unityProvider={unityProvider}
          className="w-full h-full rounded-lg"
          tabIndex={1}
        />
        <button
          onClick={onClose}
          className="absolute top-2 right-2 rounded-md border bg-background/80 backdrop-blur-sm px-2 py-1 text-xs hover:bg-background"
          title="Back to 2D view (Esc)"
        >
          Back to 2D
        </button>
      </div>
    </div>
  );
}
