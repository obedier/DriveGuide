import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @State private var tourAlerts = true
    @State private var newFeatures = true
    @State private var promotions = false
    @State private var notificationsEnabled = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandDarkNavy.ignoresSafeArea()

                List {
                    Section {
                        if !notificationsEnabled {
                            VStack(spacing: 12) {
                                Image(systemName: "bell.slash")
                                    .font(.title).foregroundStyle(.brandGold)
                                Text("Notifications are disabled")
                                    .font(.headline).foregroundStyle(.white)
                                Text("Enable in Settings to receive tour updates")
                                    .font(.caption).foregroundStyle(.white.opacity(0.5))
                                Button("Open Settings") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .buttonStyle(.borderedProminent).tint(.brandGold)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                    }
                    .listRowBackground(Color.brandNavy)

                    Section("Tour Notifications") {
                        Toggle(isOn: $tourAlerts) {
                            Label("Tour Completed", systemImage: "checkmark.circle")
                        }
                        Toggle(isOn: $tourAlerts) {
                            Label("Audio Ready", systemImage: "speaker.wave.2")
                        }
                    }
                    .listRowBackground(Color.brandNavy)

                    Section("Updates") {
                        Toggle(isOn: $newFeatures) {
                            Label("New Features", systemImage: "sparkles")
                        }
                        Toggle(isOn: $promotions) {
                            Label("Promotions & Offers", systemImage: "tag")
                        }
                    }
                    .listRowBackground(Color.brandNavy)
                }
                .scrollContentBackground(.hidden)
                .tint(.brandGold)
            }
            .navigationTitle("Notifications")
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
