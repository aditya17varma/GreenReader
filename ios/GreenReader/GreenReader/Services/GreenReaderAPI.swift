import Foundation
import os.log

class GreenReaderAPI {
    static let shared = GreenReaderAPI()

    private let baseURL = Constants.API.baseURL
    private let logger = Logger(subsystem: Constants.Logging.subsystem, category: "API")
    private let decoder: JSONDecoder

    private init() {
        decoder = JSONDecoder()
    }

    // MARK: - Courses

    func listCourses() async throws -> [Course] {
        let url = URL(string: "\(baseURL)/courses")!
        logger.info("GET \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(from: url)
        try logResponse(response, data: data)

        let result = try decoder.decode(Course.ListResponse.self, from: data)
        logger.info("Loaded \(result.courses.count) courses")
        return result.courses
    }

    func getCourse(id: String) async throws -> CourseDetail {
        let url = URL(string: "\(baseURL)/courses/\(id)")!
        logger.info("GET \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(from: url)
        try logResponse(response, data: data)

        let result = try decoder.decode(Course.DetailResponse.self, from: data)
        logger.info("Loaded course: \(result.course.name)")
        return result.course
    }

    // MARK: - Holes

    func getHole(courseId: String, holeNum: Int) async throws -> Hole {
        let url = URL(string: "\(baseURL)/courses/\(courseId)/holes/\(holeNum)")!
        logger.info("GET \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(from: url)
        try logResponse(response, data: data)

        let result = try decoder.decode(Hole.Response.self, from: data)
        logger.info("Loaded hole \(holeNum): hasSource=\(result.hole.hasSource ?? false), hasProcessed=\(result.hole.hasProcessed ?? false)")
        return result.hole
    }

    // MARK: - Best Line (Async Job)

    /// Submit a bestline request. Returns either a cached result or a job ID to poll.
    func submitBestLine(courseId: String, holeNum: Int, request: BestLineRequest) async throws -> BestLineSubmitResult {
        let url = URL(string: "\(baseURL)/courses/\(courseId)/holes/\(holeNum)/bestline")!
        logger.info("POST \(url.absoluteString)")
        logger.info("Request: ball=(\(request.ballXFt), \(request.ballZFt)), hole=(\(request.holeXFt ?? 0), \(request.holeZFt ?? 0)), stimp=\(request.stimpFt ?? Constants.Physics.defaultStimpFt)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try logResponse(response, data: data)

        // The API returns EITHER:
        // 1. {"bestLine": {...}} - cached result
        // 2. {"jobId": "...", "status": "queued"} - new job

        // Try to decode as a job first (check if jobId exists)
        if let job = try? decoder.decode(BestLineJobResponse.self, from: data),
           let jobId = job.jobId {
            logger.info("New job created: \(jobId), status=\(job.status ?? "unknown")")
            return .job(jobId: jobId, status: job.status ?? "queued")
        }

        // Otherwise, it's a cached result wrapped in {"bestLine": ...}
        let wrapper = try decoder.decode(BestLineWrapper.self, from: data)
        logger.info("Cache hit! holed=\(wrapper.bestLine.holed), miss=\(wrapper.bestLine.missFt)ft")
        return .cached(result: wrapper.bestLine)
    }

    func getBestLineStatus(courseId: String, holeNum: Int, jobId: String) async throws -> BestLineStatusResult {
        let url = URL(string: "\(baseURL)/courses/\(courseId)/holes/\(holeNum)/bestline/\(jobId)")!
        logger.info("GET \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(from: url)
        try logResponse(response, data: data)

        // The API returns EITHER:
        // 1. {"bestLine": {...}} - completed result
        // 2. {"jobId": "...", "status": "...", "updatedAt": "..."} - pending/failed

        // Try to decode as pending job first
        if let job = try? decoder.decode(BestLineJobResponse.self, from: data),
           let status = job.status,
           job.jobId != nil {
            logger.info("Job \(jobId) status: \(status)")

            if status == "failed" {
                return .failed(error: "Computation failed")
            }
            return .pending(status: status)
        }

        // Otherwise, it's the completed result wrapped in {"bestLine": ...}
        let wrapper = try decoder.decode(BestLineWrapper.self, from: data)
        logger.info("Job completed! holed=\(wrapper.bestLine.holed), miss=\(wrapper.bestLine.missFt)ft")
        return .completed(result: wrapper.bestLine)
    }

    /// Poll until the job completes
    func waitForBestLine(courseId: String, holeNum: Int, jobId: String) async throws -> BestLineResult {
        logger.info("Polling for job \(jobId)... (timeout: \(Int(Constants.Polling.timeoutSeconds))s)")
        var attempts = 0
        let maxAttempts = Constants.Polling.maxAttempts

        while attempts < maxAttempts {
            attempts += 1
            let status = try await getBestLineStatus(courseId: courseId, holeNum: holeNum, jobId: jobId)

            switch status {
            case .completed(let result):
                return result
            case .failed(let error):
                logger.error("Job \(jobId) failed: \(error)")
                throw APIError.jobFailed(message: error)
            case .pending(let statusStr):
                // Log periodically to reduce noise
                if attempts % Constants.Polling.logEveryNAttempts == 0 {
                    let elapsed = Int(Double(attempts) * Constants.Polling.intervalSeconds)
                    logger.info("Job \(jobId) still \(statusStr) (attempt \(attempts)/\(maxAttempts), \(elapsed)s elapsed)...")
                }
                try await Task.sleep(nanoseconds: Constants.Polling.intervalNanoseconds)
            }
        }

        logger.error("Job \(jobId) timed out after \(Int(Constants.Polling.timeoutSeconds)) seconds")
        throw APIError.timeout
    }

    // MARK: - Helpers

    private func logResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }

        let statusCode = httpResponse.statusCode
        let bodyPreview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"

        if statusCode >= 200 && statusCode < 300 {
            logger.info("Response \(statusCode): \(bodyPreview)")
        } else {
            logger.error("Response \(statusCode): \(bodyPreview)")
            throw APIError.httpError(statusCode: statusCode, body: bodyPreview)
        }
    }

    // MARK: - Types

    enum APIError: LocalizedError {
        case jobFailed(message: String)
        case timeout
        case httpError(statusCode: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .jobFailed(let message):
                return "Computation failed: \(message)"
            case .timeout:
                return "Computation timed out. Please try again."
            case .httpError(let code, let body):
                return "HTTP \(code): \(body)"
            }
        }
    }

    enum BestLineSubmitResult {
        case cached(result: BestLineResult)
        case job(jobId: String, status: String)
    }

    enum BestLineStatusResult {
        case completed(result: BestLineResult)
        case pending(status: String)
        case failed(error: String)
    }
}

// Response wrapper for bestline result: {"bestLine": {...}}
struct BestLineWrapper: Codable {
    let bestLine: BestLineResult
}

// Response type for job status: {"jobId": "...", "status": "...", "updatedAt": "..."}
struct BestLineJobResponse: Codable {
    let jobId: String?
    let status: String?
    let updatedAt: String?
}
