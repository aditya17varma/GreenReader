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

export async function computeBestLine(
  courseId: string,
  holeNum: number,
  params: {
    ballXFt: number;
    ballZFt: number;
    holeXFt: number;
    holeZFt: number;
    stimpFt: number;
  }
): Promise<BestLineResult> {
  const data = await fetchJson<{ bestLine: BestLineResult }>(
    `/courses/${courseId}/holes/${holeNum}/bestline`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(params),
    }
  );
  return data.bestLine;
}
