export interface Course {
  id: string;
  name: string;
  city?: string;
  state?: string;
  location?: { lat: number; lon: number };
  numHoles?: number;
}

export interface HoleSummary {
  holeNum: number;
  greenWidthFt?: number;
  greenHeightFt?: number;
  hasSource: boolean;
  hasProcessed: boolean;
}

export interface CourseDetail extends Course {
  holes: HoleSummary[];
}

export interface HoleDetail {
  courseId: string;
  holeNum: number;
  greenWidthFt: number;
  greenHeightFt: number;
  holeXzFt?: { x: number; z: number };
  hasSource: boolean;
  hasProcessed: boolean;
  sourceUrls?: Record<string, string>;
  processedUrls?: Record<string, string>;
}

export interface BestLineResult {
  ballXFt: number;
  ballZFt: number;
  holeXFt: number;
  holeZFt: number;
  stimpFt: number;
  aimOffsetDeg: number;
  speedFps: number;
  v0XFps: number;
  v0ZFps: number;
  holed: boolean;
  missFt: number;
  tEndS: number;
  pathXFt: number[];
  pathZFt: number[];
  pathYFt: number[];
}

export interface PositionFt {
  xFt: number;
  zFt: number;
}

export type PlacementMode = "flag" | "ball";
