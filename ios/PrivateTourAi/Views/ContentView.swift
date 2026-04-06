import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tourVM: TourViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Explore", systemImage: "map.fill")
                }
                .tag(0)

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
                .tag(1)

            ProfilePlaceholderView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(2)
        }
        .tint(Color("AccentCoral"))
    }
}

struct LibraryView: View {
    @EnvironmentObject var tourVM: TourViewModel
    @State private var selectedTour: Tour?

    var body: some View {
        NavigationStack {
            Group {
                if tourVM.savedTours.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("No Saved Tours")
                            .font(.title2.bold())
                        Text("Tours you create will be saved here automatically")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(tourVM.savedTours) { tour in
                            Button {
                                tourVM.openSavedTour(tour)
                                selectedTour = tour
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(tour.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        // Transport mode icon
                                        Image(systemName: transportIcon(tour.transportMode ?? "car"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(tour.locationQuery)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 12) {
                                        Label("\(tour.stops.count) stops", systemImage: "mappin.and.ellipse")
                                        Label(formatDuration(tour.durationMinutes), systemImage: "clock")
                                        if let km = tour.totalDistanceKm {
                                            Label(String(format: "%.1f km", km), systemImage: "car")
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                tourVM.deleteSavedTour(tourVM.savedTours[i])
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Library")
            .sheet(item: $selectedTour) { tour in
                TourDetailView(tour: tour)
                    .environmentObject(tourVM)
            }
        }
    }

    func transportIcon(_ mode: String) -> String {
        switch mode {
        case "walk": return "figure.walk"
        case "bike": return "bicycle"
        case "boat": return "ferry.fill"
        case "plane": return "airplane"
        default: return "car.fill"
        }
    }
}

struct ProfilePlaceholderView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                if authVM.isAuthenticated {
                    Text(authVM.displayName ?? "User")
                        .font(.title2.bold())
                    Button("Sign Out") { authVM.signOut() }
                        .foregroundStyle(.red)
                } else {
                    Text("Sign in for full tours")
                        .font(.title2.bold())
                    Button("Sign In") { authVM.signIn() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("AccentCoral"))
                }
            }
            .navigationTitle("Profile")
        }
    }
}
