import SwiftUI

struct TourRatingView: View {
    let tourTitle: String
    @Binding var rating: Int
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Rate This Tour")
                .font(.title2.bold()).foregroundStyle(.white)
            Text(tourTitle)
                .font(.subheadline).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(.spring(response: 0.2)) { rating = star }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.title)
                            .foregroundStyle(star <= rating ? .brandGold : .white.opacity(0.3))
                            .scaleEffect(star <= rating ? 1.1 : 1.0)
                    }
                }
            }
            .padding(.vertical, 10)

            HStack(spacing: 16) {
                Button("Skip") { dismiss() }
                    .foregroundStyle(.white.opacity(0.5))

                Button {
                    onSubmit()
                    dismiss()
                } label: {
                    Text("Submit Rating")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(.brandGold, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.brandNavy)
                }
                .disabled(rating == 0)
            }
        }
        .padding(30)
        .background(Color.brandNavy, in: RoundedRectangle(cornerRadius: 24))
        .padding(20)
        .presentationDetents([.height(320)])
        .presentationBackground(Color.brandDarkNavy.opacity(0.95))
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
