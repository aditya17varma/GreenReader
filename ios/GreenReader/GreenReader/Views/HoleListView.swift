import SwiftUI

struct HoleListView: View {
    let courseId: String
    let courseName: String

    @State private var course: CourseDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading holes...")
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Error: \(error)")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadCourse() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if let course = course, let holes = course.holes {
                List(holes) { hole in
                    NavigationLink(destination: GreenView(courseId: courseId, holeNum: hole.holeNum)) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Hole \(hole.holeNum)")
                                    .font(.headline)
                                if let width = hole.greenWidthFt, let height = hole.greenHeightFt {
                                    Text("\(Int(width))×\(Int(height)) ft")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if hole.hasProcessed == true {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .disabled(hole.hasProcessed != true)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "flag.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No holes available")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(courseName)
        .task {
            await loadCourse()
        }
    }

    private func loadCourse() async {
        isLoading = true
        errorMessage = nil

        do {
            course = try await GreenReaderAPI.shared.getCourse(id: courseId)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        HoleListView(courseId: "presidio-gc", courseName: "Presidio GC")
    }
}
