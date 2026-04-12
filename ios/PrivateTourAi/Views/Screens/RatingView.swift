import SwiftUI

struct TourRatingView: View {
    let tourTitle: String
    @Binding var rating: Int
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var reviewText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandDarkNavy.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text(tourTitle)
                        .font(.headline).foregroundStyle(.brandGold)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .padding(.horizontal, 20)

                    Text("How was this tour?")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.6))

                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                withAnimation(.spring(response: 0.2)) { rating = star }
                            } label: {
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.brandGold)
                                    .scaleEffect(star <= rating ? 1.1 : 1.0)
                            }
                        }
                    }
                    .padding(.vertical, 8)

                    TextField("Add a note (optional)", text: $reviewText, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(14)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandGold.opacity(0.2)))
                        .padding(.horizontal, 20)

                    Button {
                        onSubmit()
                        dismiss()
                    } label: {
                        Text("Submit Rating")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(rating > 0 ? Color.brandGold : Color.brandGold.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.brandNavy).font(.headline)
                    }
                    .disabled(rating == 0)
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationTitle("Rate Tour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.brandGold)
                }
            }
            .toolbarBackground(Color.brandDarkNavy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

struct StarRatingDisplay: View {
    let rating: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(star <= rating ? .brandGold : .white.opacity(0.2))
            }
        }
    }
}
