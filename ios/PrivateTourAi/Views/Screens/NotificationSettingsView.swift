import SwiftUI
import UserNotifications

struct SettingsView: View {
    @State private var tourAlerts = true
    @State private var newFeatures = true
    @State private var promotions = false
    @State private var notificationsEnabled = false
    @State private var useMetric = false
    @State private var autoPlayAudio = true
    @State private var cacheAudioOffline = true
    @AppStorage("voiceEngine") private var voiceEngine = "google"
    @AppStorage("voiceQuality") private var voiceQuality = "premium"
    @AppStorage("navigationEngine") private var navigationEngine = "apple"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandDarkNavy.ignoresSafeArea()

                List {
                    // MARK: - Tour Defaults
                    Section("Tour Defaults") {
                        Toggle(isOn: $autoPlayAudio) {
                            Label("Auto-Play Audio", systemImage: "play.circle")
                        }
                        Toggle(isOn: $cacheAudioOffline) {
                            Label("Cache Audio Offline", systemImage: "arrow.down.circle")
                        }
                        Toggle(isOn: $useMetric) {
                            Label("Use Metric Units", systemImage: "ruler")
                        }
                    }
                    .listRowBackground(Color.brandNavy)

                    // MARK: - Voice
                    Section("Voice Engine") {
                        Picker("Engine", selection: $voiceEngine) {
                            Text("Google Cloud (Natural)").tag("google")
                            Text("Kokoro (Ultra-Realistic)").tag("kokoro")
                        }
                        .pickerStyle(.menu)

                        if voiceEngine == "google" {
                            Picker("Quality", selection: $voiceQuality) {
                                Text("Standard").tag("standard")
                                Text("Premium (Journey)").tag("premium")
                            }
                            .pickerStyle(.menu)
                        } else {
                            HStack {
                                Image(systemName: "sparkles").foregroundStyle(.brandGold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Kokoro 82M").font(.subheadline)
                                    Text("Open-source, ultra-natural speech synthesis").font(.caption).foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.brandNavy)

                    // MARK: - Navigation
                    Section("Navigation") {
                        Picker("Map Engine", selection: $navigationEngine) {
                            Text("Apple Maps").tag("apple")
                            Text("MapLibre (Open Source)").tag("ferrostar")
                        }
                        .pickerStyle(.menu)

                        if navigationEngine == "ferrostar" {
                            HStack {
                                Image(systemName: "car.fill").foregroundStyle(.brandGold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("MapLibre + Ferrostar").font(.subheadline)
                                    Text("Open-source maps with OSRM turn-by-turn routing").font(.caption).foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        } else {
                            HStack {
                                Image(systemName: "map.fill").foregroundStyle(.brandGold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Apple MapKit").font(.subheadline)
                                    Text("Route polylines with turn instructions overlay").font(.caption).foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.brandNavy)

                    // MARK: - Notifications
                    Section("Notifications") {
                        if !notificationsEnabled {
                            Button {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "bell.slash").foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Notifications Disabled").foregroundStyle(.white)
                                        Text("Tap to enable in iOS Settings").font(.caption).foregroundStyle(.white.opacity(0.4))
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right").foregroundStyle(.white.opacity(0.3))
                                }
                            }
                        } else {
                            Toggle(isOn: $tourAlerts) {
                                Label("Tour Completed", systemImage: "checkmark.circle")
                            }
                            Toggle(isOn: $tourAlerts) {
                                Label("Audio Ready", systemImage: "speaker.wave.2")
                            }
                            Toggle(isOn: $newFeatures) {
                                Label("New Features", systemImage: "sparkles")
                            }
                            Toggle(isOn: $promotions) {
                                Label("Promotions & Offers", systemImage: "tag")
                            }
                        }
                    }
                    .listRowBackground(Color.brandNavy)

                    // MARK: - About
                    Section("About") {
                        HStack {
                            Label("Version", systemImage: "info.circle")
                            Spacer()
                            Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Link(destination: URL(string: "https://waipoint.o11r.com/privacy")!) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                        Link(destination: URL(string: "https://waipoint.o11r.com/terms")!) {
                            Label("Terms of Service", systemImage: "doc.text")
                        }
                        Link(destination: URL(string: "https://waipoint.o11r.com/support")!) {
                            Label("Help & Support", systemImage: "questionmark.circle")
                        }
                    }
                    .listRowBackground(Color.brandNavy)
                }
                .scrollContentBackground(.hidden)
                .tint(.brandGold)
                .foregroundStyle(.white)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.brandGold)
                }
            }
            .toolbarBackground(Color.brandDarkNavy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear { checkNotificationStatus() }
        }
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }
}
