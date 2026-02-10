import SwiftUI

struct CourseListView: View {
    @State private var courses: [Course] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading courses...")
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Error: \(error)")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadCourses() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    List(courses) { course in
                        NavigationLink(destination: HoleListView(courseId: course.id, courseName: course.name)) {
                            VStack(alignment: .leading) {
                                Text(course.name)
                                    .font(.headline)
                                if let city = course.city, let state = course.state {
                                    Text("\(city), \(state)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                if let numHoles = course.numHoles {
                                    Text("\(numHoles) holes")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Courses")
        }
        .task {
            await loadCourses()
        }
    }

    private func loadCourses() async {
        isLoading = true
        errorMessage = nil

        do {
            courses = try await GreenReaderAPI.shared.listCourses()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    CourseListView()
}
