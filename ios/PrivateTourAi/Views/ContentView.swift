import SwiftUI
import AuthenticationServices

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

            ProfileView()
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
                                            let isBoat = tour.transportMode == "boat"
                                            let icon = transportIcon(tour.transportMode ?? "car")
                                            if isBoat {
                                                Label(String(format: "%.1f nm", km * 0.539957), systemImage: icon)
                                            } else {
                                                Label(String(format: "%.1f mi", km * 0.621371), systemImage: icon)
                                            }
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

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showSignIn = false

    var body: some View {
        NavigationStack {
            List {
                if authVM.isAuthenticated {
                    // Profile section
                    Section {
                        HStack(spacing: 14) {
                            if let url = authVM.photoURL {
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 50))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(authVM.displayName ?? "User")
                                    .font(.headline)
                                if let email = authVM.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Subscription section
                    Section("Subscription") {
                        HStack {
                            Text("Plan")
                            Spacer()
                            Text(authVM.tier.rawValue.capitalized)
                                .foregroundStyle(Color("AccentCoral"))
                                .fontWeight(.semibold)
                        }
                        if !authVM.subscription.tier.isUnlimited {
                            Button("Upgrade to Premium") {
                                // TODO: Show paywall
                            }
                            .foregroundStyle(Color("AccentCoral"))
                        }
                        Button("Restore Purchases") {
                            Task { await authVM.subscription.restorePurchases() }
                        }
                    }

                    // Account section
                    Section("Account") {
                        Button("Sign Out", role: .destructive) {
                            authVM.signOut()
                        }
                        Button("Delete Account", role: .destructive) {
                            authVM.deleteAccount()
                        }
                    }
                } else {
                    // Sign-in section
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                            Text("Sign in to Roamly")
                                .font(.title2.bold())
                            Text("Save tours, sync across devices, and unlock premium features")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }

                    Section {
                        // Google Sign-In
                        Button {
                            authVM.signInWithGoogle()
                        } label: {
                            HStack {
                                Image(systemName: "g.circle.fill")
                                    .font(.title2)
                                Text("Continue with Google")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }

                        // Apple Sign-In
                        Button {
                            authVM.signInWithApple()
                        } label: {
                            HStack {
                                Image(systemName: "apple.logo")
                                    .font(.title2)
                                Text("Continue with Apple")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }

                        // Email sign-in
                        VStack(spacing: 10) {
                            TextField("Email", text: $authVM.emailText)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                            SecureField("Password", text: $authVM.passwordText)
                                .textContentType(.password)
                            Button {
                                authVM.signInWithEmail()
                            } label: {
                                Text("Sign In with Email")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color("AccentCoral"))
                            .disabled(authVM.emailText.isEmpty || authVM.passwordText.isEmpty)
                        }
                    }

                    if let error = authVM.authError {
                        Section {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}
