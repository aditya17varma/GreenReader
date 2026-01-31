// Resource names
export const BUCKET_NAME = "greenreader-data";
export const TABLE_NAME = "greenreader-catalog";
export const API_NAME = "greenreader-api";
export const CDN_COMMENT = "GreenReader CDN";
export const LAYER_NAME = "greenreader-shared";

// Lambda function names
export const LAMBDA_NAMES = {
  listCourses: "greenreader-list-courses",
  createCourse: "greenreader-create-course",
  getCourse: "greenreader-get-course",
  getHole: "greenreader-get-hole",
  registerHole: "greenreader-register-hole",
  updateHole: "greenreader-update-hole",
  computeBestline: "greenreader-compute-bestline",
} as const;
