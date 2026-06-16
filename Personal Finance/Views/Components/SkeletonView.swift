import SwiftUI

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear,                   location: 0),
                            .init(color: .white.opacity(0.55),     location: 0.4),
                            .init(color: .white.opacity(0.55),     location: 0.6),
                            .init(color: .clear,                   location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2.5)
                    .offset(x: geo.size.width * phase)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

// MARK: - Skeleton shapes

struct SkeletonLine: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
            .shimmer()
    }
}

struct SkeletonCircle: View {
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(.systemGray5))
            .frame(width: size, height: size)
            .shimmer()
    }
}

// MARK: - Transaction row skeleton

struct TransactionRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonCircle(size: 42)

            VStack(alignment: .leading, spacing: 6) {
                SkeletonLine(width: 120, height: 13)
                SkeletonLine(width: 80, height: 11)
            }

            Spacer()

            SkeletonLine(width: 72, height: 13)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Full skeleton list (mimics grouped list)

struct TransactionListSkeleton: View {
    var body: some View {
        List {
            ForEach(0..<2) { _ in
                Section {
                    ForEach(0..<5, id: \.self) { _ in
                        TransactionRowSkeleton()
                    }
                } header: {
                    SkeletonLine(width: 140, height: 11)
                        .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .allowsHitTesting(false)
    }
}
