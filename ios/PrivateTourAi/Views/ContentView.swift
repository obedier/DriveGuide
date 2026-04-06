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

            LibraryPlaceholderView()
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

struct LibraryPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("Your Tours")
                    .font(.title2.bold())
                Text("Tours you create will appear here")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Library")
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
