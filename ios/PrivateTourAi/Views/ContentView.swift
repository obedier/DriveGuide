import SwiftUI
import AuthenticationServices

struct ContentView: View {
    @EnvironmentObject var tourVM: TourViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Explore", systemImage: "safari.fill") }
                .tag(0)

            LibraryView()
                .tabItem { Label("Library", systemImage: "book.fill") }
                .tag(1)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(2)
        }
        .tint(.brandGold)
    }
}

// MARK: - Library (Stitch design: dark green cards, gold text)

struct LibraryView: View {
    @EnvironmentObject var tourVM: TourViewModel
    @State private var selectedTour: Tour?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandDarkNavy.ignoresSafeArea()

                if tourVM.savedTours.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "safari")
                            .font(.system(size: 60))
                            .foregroundStyle(.brandGold.opacity(0.3))
                        Text("No Saved Tours")
                            .font(.title2.bold()).foregroundStyle(.white)
                        Text("Tours you create will appear here")
                            .foregroundStyle(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(tourVM.savedTours) { tour in
                                Button {
                                    tourVM.openSavedTour(tour)
                                    selectedTour = tour
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(tour.title)
                                                .font(.headline).foregroundStyle(.brandGold)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                            Image(systemName: transportIcon(tour.transportMode ?? "car"))
                                                .foregroundStyle(.brandGold.opacity(0.5))
                                        }
                                        Text(tour.locationQuery)
                                            .font(.caption).foregroundStyle(.white.opacity(0.4))
                                        HStack(spacing: 14) {
                                            Label("\(tour.stops.count) Stops", systemImage: "mappin")
                                            Label(formatDuration(tour.durationMinutes), systemImage: "clock")
                                            if let km = tour.totalDistanceKm {
                                                if tour.transportMode == "boat" {
                                                    Label(String(format: "%.1f nm", km * 0.539957), systemImage: "ferry.fill")
                                                } else {
                                                    Label(String(format: "%.1f mi", km * 0.621371), systemImage: transportIcon(tour.transportMode ?? "car"))
                                                }
                                            }
                                        }
                                        .font(.caption2).foregroundStyle(.white.opacity(0.35))
                                    }
                                    .padding(16)
                                    .background(Color.brandGreen.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.brandGold.opacity(0.1)))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { tourVM.deleteSavedTour(tour) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.top, 8)
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("wAIpoint").font(.caption).foregroundStyle(.brandGold)
                        Text("Tour Library").font(.headline.bold()).foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(Color.brandDarkNavy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(item: $selectedTour) { tour in
                TourDetailView(tour: tour).environmentObject(tourVM)
            }
        }
    }

    func transportIcon(_ mode: String) -> String {
        switch mode {
        case "walk": return "figure.walk"; case "bike": return "bicycle"
        case "boat": return "ferry.fill"; case "plane": return "airplane"
        default: return "car.fill"
        }
    }
}

// MARK: - Profile (Stitch design: navy bg, gold buttons, tier badge)

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandDarkNavy.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        if authVM.isAuthenticated {
                            // Profile header
                            HStack(spacing: 14) {
                                if let url = authVM.photoURL {
                                    AsyncImage(url: url) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Image(systemName: "person.circle.fill")
                                            .font(.system(size: 50)).foregroundStyle(.brandGold)
                                    }
                                    .frame(width: 56, height: 56).clipShape(Circle())
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 50)).foregroundStyle(.brandGold)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(authVM.displayName ?? "Explorer")
                                        .font(.title3.bold()).foregroundStyle(.white)
                                    if let email = authVM.email {
                                        Text(email).font(.caption).foregroundStyle(.white.opacity(0.4))
                                    }
                                }
                                Spacer()
                                // Tier badge
                                Text(authVM.tier.rawValue.capitalized)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.brandGold, in: Capsule())
                                    .foregroundStyle(.brandNavy)
                            }
                            .padding(20)

                            // Menu items
                            VStack(spacing: 0) {
                                ProfileMenuItem(icon: "bell.fill", title: "Notifications")
                                ProfileMenuItem(icon: "questionmark.circle", title: "Help & Support")
                                Button { authVM.signOut() } label: {
                                    ProfileMenuItem(icon: "arrow.right.square", title: "Sign Out")
                                }
                            }
                            .background(Color.brandNavy.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal, 20)

                        } else {
                            // Sign-in view
                            VStack(spacing: 20) {
                                Image(systemName: "safari.fill")
                                    .font(.system(size: 60)).foregroundStyle(.brandGold)
                                    .padding(.top, 40)
                                Text("Welcome to wAIpoint")
                                    .font(.title2.bold()).foregroundStyle(.white)
                                Text("Sign in to save tours, sync across devices, and unlock premium features")
                                    .font(.subheadline).foregroundStyle(.white.opacity(0.5))
                                    .multilineTextAlignment(.center).padding(.horizontal, 30)
                            }
                            .padding(.bottom, 30)

                            // Apple Sign-In
                            SignInWithAppleButton(.continue) { request in
                                let hashedNonce = authVM.prepareAppleNonce()
                                request.requestedScopes = [.fullName, .email]
                                request.nonce = hashedNonce
                            } onCompletion: { result in
                                authVM.handleAppleResult(result)
                            }
                            .signInWithAppleButtonStyle(.white)
                            .frame(height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 30)

                            // Google Sign-In (matching gold style)
                            Button { authVM.signInWithGoogle() } label: {
                                HStack(spacing: 10) {
                                    Text("G").font(.title2.bold())
                                    Text("Continue with Google").fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity).frame(height: 54)
                                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.black)
                            }
                            .padding(.horizontal, 30)

                            // Email/Password
                            VStack(spacing: 12) {
                                TextField("Email", text: $authVM.emailText, prompt: Text("Email").foregroundStyle(.white.opacity(0.4)))
                                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .padding(14)
                                    .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.white)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandGold.opacity(0.3), lineWidth: 1))

                                SecureField("Password", text: $authVM.passwordText, prompt: Text("Password").foregroundStyle(.white.opacity(0.4)))
                                    .textContentType(.password)
                                    .padding(14)
                                    .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.white)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandGold.opacity(0.3), lineWidth: 1))

                                Button { authVM.signInWithEmail() } label: {
                                    Text("Sign In with Email").fontWeight(.semibold)
                                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                                        .background(Color.brandGold.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(.brandGold)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandGold.opacity(0.5), lineWidth: 1))
                                }
                                .disabled(authVM.emailText.isEmpty || authVM.passwordText.isEmpty)

                                // Forgot password
                                Button {
                                    authVM.resetPassword()
                                } label: {
                                    Text("Forgot Password?")
                                        .font(.caption)
                                        .foregroundStyle(.brandGold.opacity(0.7))
                                }
                            }
                            .padding(.horizontal, 30).padding(.top, 10)

                            if let error = authVM.authError {
                                Text(error)
                                    .font(.caption).foregroundStyle(.red)
                                    .padding(10)
                                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                                    .padding(.horizontal, 30)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("")
            .toolbarBackground(Color.brandDarkNavy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

struct ProfileMenuItem: View {
    let icon: String
    let title: String

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.brandGold).frame(width: 24)
            Text(title).foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}
