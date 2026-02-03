import type { Course, CourseDetail, HoleDetail, BestLineResult } from "./types";

const BASE_URL = import.meta.env.VITE_API_URL as string;

async function fetchJson<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE_URL}${path}`, init);
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`API ${res.status}: ${body}`);
  }
  return res.json() as Promise<T>;
}

export async function listCourses(): Promise<Course[]> {
  const data = await fetchJson<{ courses: Course[] }>("/courses");
  return data.courses;
}

export async function getCourse(courseId: string): Promise<CourseDetail> {
  const data = await fetchJson<{ course: CourseDetail }>(
    `/courses/${courseId}`
  );
  return data.course;
}

export async function getHole(
  courseId: string,
  holeNum: number
): Promise<HoleDetail> {
  const data = await fetchJson<{ hole: HoleDetail }>(
    `/courses/${courseId}/holes/${holeNum}`
  );
  return data.hole;
}

export type ComputeStatus = "submitting" | "queued" | "running" | "loading";

export async function computeBestLine(
  courseId: string,
  holeNum: number,
  params: {
    ballXFt: number;
    ballZFt: number;
    holeXFt: number;
    holeZFt: number;
    stimpFt: number;
  },
  onStatus?: (status: ComputeStatus) => void
): Promise<BestLineResult> {
  onStatus?.("submitting");
  const data = await fetchJson<
    | { bestLine: BestLineResult }
    | { jobId: string; status: string }
  >(
    `/courses/${courseId}/holes/${holeNum}/bestline`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(params),
    }
  );
  if ("bestLine" in data) {
    return data.bestLine;
  }

  return pollBestLine(courseId, holeNum, data.jobId, onStatus);
}

async function pollBestLine(
  courseId: string,
  holeNum: number,
  jobId: string,
  onStatus?: (status: ComputeStatus) => void
): Promise<BestLineResult> {
  const timeoutMs = 120_000;
  const intervalMs = 2_000;
  const start = Date.now();

  onStatus?.("queued");

  while (Date.now() - start < timeoutMs) {
    const res = await fetch(
      `${BASE_URL}/courses/${courseId}/holes/${holeNum}/bestline/${jobId}`
    );

    if (!res.ok) {
      const body = await res.text();
      throw new Error(`Best line computation failed: ${body}`);
    }

    const data = (await res.json()) as
      | { bestLine: BestLineResult }
      | { jobId: string; status: string; updatedAt?: string };

    if ("bestLine" in data) {
      onStatus?.("loading");
      return data.bestLine;
    }

    if ("status" in data && data.status === "running") {
      onStatus?.("running");
    }

    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }

  throw new Error("Best line computation timed out");
}
