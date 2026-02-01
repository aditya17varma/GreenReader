import { useEffect, useState } from "react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { listCourses, getCourse } from "@/lib/api";
import type { Course, HoleSummary } from "@/lib/types";

interface CourseSelectorProps {
  onHoleSelect: (courseId: string, holeNum: number) => void;
}

export function CourseSelector({ onHoleSelect }: CourseSelectorProps) {
  const [courses, setCourses] = useState<Course[]>([]);
  const [holes, setHoles] = useState<HoleSummary[]>([]);
  const [selectedCourseId, setSelectedCourseId] = useState<string>("");
  const [selectedHoleNum, setSelectedHoleNum] = useState<string>("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    listCourses()
      .then(setCourses)
      .catch((e) => setError(e.message));
  }, []);

  async function handleCourseChange(courseId: string) {
    setSelectedCourseId(courseId);
    setSelectedHoleNum("");
    setHoles([]);
    setLoading(true);
    setError(null);
    try {
      const detail = await getCourse(courseId);
      setHoles(detail.holes);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load course");
    } finally {
      setLoading(false);
    }
  }

  function handleHoleChange(holeNum: string) {
    setSelectedHoleNum(holeNum);
    onHoleSelect(selectedCourseId, Number(holeNum));
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-2">
        <Label htmlFor="course-select">Course</Label>
        <Select value={selectedCourseId} onValueChange={handleCourseChange}>
          <SelectTrigger id="course-select" className="w-full">
            <SelectValue placeholder="Select a course" />
          </SelectTrigger>
          <SelectContent>
            {courses.map((c) => (
              <SelectItem key={c.id} value={c.id}>
                {c.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="flex flex-col gap-2">
        <Label htmlFor="hole-select">Hole</Label>
        <Select
          value={selectedHoleNum}
          onValueChange={handleHoleChange}
          disabled={holes.length === 0 || loading}
        >
          <SelectTrigger id="hole-select" className="w-full">
            <SelectValue
              placeholder={loading ? "Loading..." : "Select a hole"}
            />
          </SelectTrigger>
          <SelectContent>
            {holes.map((h) => (
              <SelectItem key={h.holeNum} value={String(h.holeNum)}>
                Hole {h.holeNum}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}
    </div>
  );
}
