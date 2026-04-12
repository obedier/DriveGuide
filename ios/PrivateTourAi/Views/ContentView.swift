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
    @State private var selectedSection = 0  // 0=Library, 1=Archive, 2=Community
    @State private var showRating = false
    @State private var ratingTour: Tour?
    @State private var showCommunityRating = false
    @State private var ratingTourId = ""
    @State private var ratingTourTitle = ""
    @State private var ratingValue = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandDarkNavy.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Section picker — tight to nav title
                    Picker("", selection: $selectedSection) {
                        Text("Library").tag(0)
                        Text("Archive").tag(1)
                        Text("Community").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .colorMultiply(.brandGold)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 6)

                    if selectedSection == 0 {
                        libraryContent
                    } else if selectedSection == 1 {
                        archiveContent
                    } else {
                        communityContent
                    }

                    // Community message banner
                    if let msg = tourVM.communityMessage {
                        HStack {
                            Image(systemName: msg.contains("Failed") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(msg.contains("Failed") ? .orange : .green)
                            Text(msg).font(.caption).foregroundStyle(.white)
                            Spacer()
                            Button { tourVM.communityMessage = nil } label: {
                                Image(systemName: "xmark").font(.caption).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .padding(12)
                        .background(Color.brandNavy.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("wAIpoint").font(.caption).foregroundStyle(.brandGold)
                        Text("Tours").font(.headline.bold()).foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(Color.brandDarkNavy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(item: $selectedTour) { tour in
                TourDetailView(tour: tour).environmentObject(tourVM)
            }
            .sheet(isPresented: $showRating) {
                if let tour = ratingTour {
                    TourRatingView(tourTitle: tour.title, rating: $ratingValue) {
                        tourVM.rateTour(tour, rating: ratingValue)
                    }
                }
            }
            .sheet(isPresented: $showCommunityRating) {
                RateTourSheet(tourTitle: ratingTourTitle, tourId: ratingTourId, isPresented: $showCommunityRating) {
                    Task { await tourVM.loadCommunityTours() }
                }
            }
        }
    }

    // MARK: - Library Content

    var libraryContent: some View {
        Group {
            if tourVM.savedTours.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "safari").font(.system(size: 60)).foregroundStyle(.brandGold.opacity(0.3))
                    Text("No Saved Tours").font(.title2.bold()).foregroundStyle(.white)
                    Text("Tours you create will appear here").foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(tourVM.savedTours) { tour in
                        TourListCard(tour: tour, rating: tourVM.getRating(for: tour.id)) {
                            tourVM.openSavedTour(tour)
                            selectedTour = tour
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { tourVM.deleteSavedTour(tour) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { tourVM.archiveTour(tour) } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                // Share to Community (upload to backend)
                                tourVM.shareToCommunity(tour)
                            } label: {
                                Label("Community", systemImage: "globe")
                            }
                            .tint(.green)

                            if let shareUrl = tourVM.shareTourById(tour) {
                                ShareLink(item: shareUrl) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .tint(.brandGold)
                            }

                            Button { ratingTour = tour; ratingValue = tourVM.getRating(for: tour.id) ?? 0; showRating = true } label: {
                                Label("Rate", systemImage: "star.fill")
                            }
                            .tint(.yellow)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Archive Content

    var archiveContent: some View {
        Group {
            if tourVM.archivedTours.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "archivebox").font(.system(size: 60)).foregroundStyle(.white.opacity(0.2))
                    Text("No Archived Tours").font(.title2.bold()).foregroundStyle(.white)
                    Text("Long-press a tour to archive it").foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Delete All") { tourVM.deleteAllArchived() }
                            .font(.caption).foregroundStyle(.red)
                            .padding(.trailing, 20).padding(.top, 8)
                    }
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(tourVM.archivedTours) { tour in
                                TourListCard(tour: tour, rating: nil) {
                                    tourVM.openSavedTour(tour)
                                    selectedTour = tour
                                }
                                .opacity(0.7)
                                .contextMenu {
                                    Button { tourVM.unarchiveTour(tour) } label: { Label("Unarchive", systemImage: "tray.and.arrow.up") }
                                    Button(role: .destructive) { tourVM.deleteArchivedTour(tour) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.top, 4)
                    }
                }
            }
        }
    }

    // MARK: - Community Content

    var communityContent: some View {
        Group {
            if tourVM.isLoadingCommunity {
                VStack(spacing: 16) {
                    ProgressView().tint(.brandGold)
                    Text("Loading community tours...").foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxHeight: .infinity)
            } else if tourVM.communityTours.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "globe").font(.system(size: 60)).foregroundStyle(.brandGold.opacity(0.3))
                    Text("Community Tours").font(.title2.bold()).foregroundStyle(.white)
                    Text("Discover tours shared by other explorers.\nBe the first to share one!").foregroundStyle(.white.opacity(0.4)).multilineTextAlignment(.center)

                    if !tourVM.savedTours.isEmpty {
                        Menu {
                            ForEach(tourVM.savedTours) { tour in
                                Button(tour.title) { tourVM.shareToCommunity(tour) }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share a Tour to Community")
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(.brandGold.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.brandGold)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brandGold.opacity(0.3)))
                        }
                        .padding(.horizontal, 30)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(tourVM.communityTours) { item in
                            CommunityTourCard(item: item, onTap: {
                                if let shareId = item.share_id {
                                    Task {
                                        do {
                                            let tour = try await APIClient.shared.getSharedTour(shareId: shareId)
                                            tourVM.currentTour = tour
                                            tourVM.showTourDetail = true
                                        } catch {
                                            tourVM.communityMessage = "Failed to load tour"
                                        }
                                    }
                                }
                            }, onRate: {
                                ratingTourId = item.id
                                ratingTourTitle = item.title
                                showCommunityRating = true
                            })
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
        }
        .task { await tourVM.loadCommunityTours() }
    }

    func transportIcon(_ mode: String) -> String {
        switch mode {
        case "walk": return "figure.walk"; case "bike": return "bicycle"
        case "boat": return "ferry.fill"; case "plane": return "airplane"
        default: return "car.fill"
        }
    }
}

// MARK: - Reusable Tour List Card

struct TourListCard: View {
    let tour: Tour
    let rating: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tour.title).font(.headline).foregroundStyle(.brandGold).multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: transportIcon(tour.transportMode ?? "car")).foregroundStyle(.brandGold.opacity(0.5))
                }
                Text(tour.locationQuery).font(.caption).foregroundStyle(.white.opacity(0.4))
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
                    if let r = rating {
                        StarRatingDisplay(rating: r)
                    }
                }
                .font(.caption2).foregroundStyle(.white.opacity(0.35))
            }
            .padding(16)
            .background(Color.brandGreen.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.brandGold.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    func transportIcon(_ mode: String) -> String {
        switch mode {
        case "walk": return "figure.walk"; case "bike": return "bicycle"
        case "boat": return "ferry.fill"; case "plane": return "airplane"
        default: return "car.fill"
        }
    }
}

// MARK: - Community Tour Card

struct CommunityTourCard: View {
    let item: APIClient.CommunityTourItem
    let onTap: () -> Void
    let onRate: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.title).font(.headline).foregroundStyle(.brandGold).multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: transportIcon(item.transport_mode)).foregroundStyle(.brandGold.opacity(0.5))
                }
                Text(item.location).font(.caption).foregroundStyle(.white.opacity(0.4))

                // 5-star rating display
                HStack(spacing: 4) {
                    FiveStarDisplay(rating: item.rating ?? 0)
                    if let count = item.rating_count, count > 0 {
                        Text("(\(count))").font(.caption2).foregroundStyle(.white.opacity(0.3))
                    }
                    Spacer()
                    Button { onRate() } label: {
                        Text("Rate").font(.caption2.bold()).foregroundStyle(.brandGold)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.brandGold.opacity(0.15), in: Capsule())
                    }
                }

                HStack(spacing: 14) {
                    Label("\(item.duration_minutes) min", systemImage: "clock")
                    if let km = item.distance_km {
                        Label(String(format: "%.1f mi", km * 0.621371), systemImage: transportIcon(item.transport_mode))
                    }
                }
                .font(.caption2).foregroundStyle(.white.opacity(0.35))
            }
            .padding(16)
            .background(Color.brandGreen.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.brandGold.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    func transportIcon(_ mode: String) -> String {
        switch mode {
        case "walk": return "figure.walk"; case "bike": return "bicycle"
        case "boat": return "ferry.fill"; case "plane": return "airplane"
        default: return "car.fill"
        }
    }
}

// MARK: - 5-Star Display

struct FiveStarDisplay: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: starIcon(for: star))
                    .font(.caption2)
                    .foregroundStyle(.brandGold)
            }
        }
    }

    private func starIcon(for star: Int) -> String {
        let value = rating
        if Double(star) <= value { return "star.fill" }
        if Double(star) - 0.5 <= value { return "star.leadinghalf.filled" }
        return "star"
    }
}

// MARK: - Rate Tour Sheet

struct RateTourSheet: View {
    let tourTitle: String
    let tourId: String
    @Binding var isPresented: Bool
    var onRated: () -> Void

    @State private var selectedRating = 0
    @State private var reviewText = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandDarkNavy.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text(tourTitle)
                        .font(.headline).foregroundStyle(.brandGold)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)

                    Text("How was this tour?")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.6))

                    // Tap-to-rate stars
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { selectedRating = star }
                            } label: {
                                Image(systemName: star <= selectedRating ? "star.fill" : "star")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.brandGold)
                            }
                        }
                    }
                    .padding(.vertical, 8)

                    // Review text
                    TextField("Write a review (optional)", text: $reviewText, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(14)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandGold.opacity(0.2)))
                        .padding(.horizontal, 20)

                    if let error = errorMessage {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }

                    // Submit button
                    Button {
                        submitRating()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView().tint(.brandNavy)
                            }
                            Text("Submit Rating")
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(selectedRating > 0 ? Color.brandGold : Color.brandGold.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.brandNavy).font(.headline)
                    }
                    .disabled(selectedRating == 0 || isSubmitting)
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationTitle("Rate Tour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                        .foregroundStyle(.brandGold)
                }
            }
            .toolbarBackground(Color.brandDarkNavy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func submitRating() {
        isSubmitting = true
        Task {
            do {
                try await APIClient.shared.rateTour(
                    tourId: tourId,
                    rating: selectedRating,
                    review: reviewText.isEmpty ? nil : reviewText
                )
                isPresented = false
                onRated()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - Profile (Stitch design: navy bg, gold buttons, tier badge)

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var store = StoreKitService.shared
    @State private var showPaywall = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

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
                                Text(store.isPremium ? store.currentTier : "Free")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(store.isPremium ? Color.brandGold : Color.white.opacity(0.2), in: Capsule())
                                    .foregroundStyle(store.isPremium ? .brandNavy : .white)
                            }
                            .padding(20)

                            // Subscription section
                            if !store.isPremium {
                                Button { showPaywall = true } label: {
                                    HStack {
                                        Image(systemName: "crown.fill").foregroundStyle(.brandGold)
                                        Text("Upgrade to Premium").fontWeight(.semibold).foregroundStyle(.brandGold)
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(.brandGold.opacity(0.5))
                                    }
                                    .padding(16)
                                    .background(Color.brandGold.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.brandGold.opacity(0.3)))
                                }
                                .padding(.horizontal, 20)
                            } else {
                                HStack {
                                    Image(systemName: "crown.fill").foregroundStyle(.brandGold)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Premium \(store.currentTier)").font(.subheadline.bold()).foregroundStyle(.brandGold)
                                        Text("Unlimited tours & audio").font(.caption).foregroundStyle(.white.opacity(0.4))
                                    }
                                    Spacer()
                                    Button("Manage") {
                                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                            UIApplication.shared.open(url)
                                        }
                                    }
                                    .font(.caption).foregroundStyle(.brandGold)
                                }
                                .padding(16)
                                .background(Color.brandGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal, 20)
                            }

                            // Menu items
                            VStack(spacing: 0) {
                                NavigationLink {
                                    SettingsView()
                                } label: {
                                    ProfileMenuItem(icon: "gearshape.fill", title: "Settings")
                                }
                                Button {
                                    Task { await store.restorePurchases() }
                                } label: {
                                    ProfileMenuItem(icon: "arrow.clockwise", title: "Restore Purchases")
                                }
                                Button { authVM.signOut() } label: {
                                    ProfileMenuItem(icon: "arrow.right.square", title: "Sign Out")
                                }
                            }
                            .background(Color.brandNavy.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal, 20)

                            // Delete account
                            Button { showDeleteConfirm = true } label: {
                                Text("Delete Account")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.6))
                            }
                            .padding(.top, 16)

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

                            // Apple Sign-In (gold overlay on native button)
                            ZStack {
                                SignInWithAppleButton(.continue) { request in
                                    let hashedNonce = authVM.prepareAppleNonce()
                                    request.requestedScopes = [.fullName, .email]
                                    request.nonce = hashedNonce
                                } onCompletion: { result in
                                    authVM.handleAppleResult(result)
                                }
                                .signInWithAppleButtonStyle(.black)
                                .frame(height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .opacity(0.01) // invisible but tappable

                                // Gold visual layer
                                HStack(spacing: 10) {
                                    Image(systemName: "apple.logo").font(.title3)
                                    Text("Continue with Apple").fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity).frame(height: 54)
                                .background(
                                    LinearGradient(colors: [.brandGold, Color(red: 0.85, green: 0.73, blue: 0.45)],
                                                   startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                                .foregroundStyle(.brandNavy)
                                .allowsHitTesting(false) // taps pass through to real button
                            }
                            .padding(.horizontal, 30)

                            // Google Sign-In (matching gold)
                            Button { authVM.signInWithGoogle() } label: {
                                HStack(spacing: 10) {
                                    Text("G").font(.title2.bold())
                                    Text("Continue with Google").fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity).frame(height: 54)
                                .background(
                                    LinearGradient(colors: [.brandGold.opacity(0.85), Color(red: 0.85, green: 0.73, blue: 0.45).opacity(0.85)],
                                                   startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                                .foregroundStyle(.brandNavy)
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
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .alert("Delete Account", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Everything", role: .destructive) {
                    isDeleting = true
                    Task {
                        do {
                            try await AuthService.shared.deleteAccount()
                        } catch {
                            print("[Profile] Delete error: \(error)")
                        }
                        isDeleting = false
                    }
                }
            } message: {
                Text("This will permanently delete your account, all saved tours, ratings, and subscription data. This cannot be undone.")
            }
            .overlay {
                if isDeleting {
                    ZStack {
                        Color.black.opacity(0.5).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().tint(.brandGold)
                            Text("Deleting account...").foregroundStyle(.white)
                        }
                    }
                }
            }
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
