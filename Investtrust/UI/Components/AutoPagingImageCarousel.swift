import SwiftUI

/// Identity for `.task(id:)` — tuples of `[String]` are not `Hashable` in Swift.
private struct CarouselAutoAdvanceTaskID: Hashable {
    let references: [String]
    let reduceMotionEffective: Bool
}

/// Horizontally paged images with automatic advance (and manual swipe). Use only when `references` is non-empty.
struct AutoPagingImageCarousel: View {
    let references: [String]
    var height: CGFloat = 190
    var cornerRadius: CGFloat = 16
    /// Seconds between automatic page changes (only when `references.count > 1`).
    var autoAdvanceInterval: TimeInterval = 4

    @State private var selection = 0
    @Environment(\.effectiveReduceMotion) private var effectiveReduceMotion

    var body: some View {
        Group {
            if references.isEmpty {
                Color(.systemGray5)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else if references.count == 1, let only = references.first {
                StorageBackedAsyncImage(reference: only, height: height, cornerRadius: cornerRadius)
            } else {
                TabView(selection: $selection) {
                    ForEach(Array(references.indices), id: \.self) { index in
                        StorageBackedAsyncImage(
                            reference: references[index],
                            height: height,
                            cornerRadius: cornerRadius
                        )
                        .tag(index) 
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: height)
                .task(id: CarouselAutoAdvanceTaskID(references: references, reduceMotionEffective: effectiveReduceMotion)) {
                    // Preload a few neighbors first; avoid pulling every full-size image at once on slow links.
                    await CachedImageLoader.preload(references: Array(references.prefix(4)))
                    guard references.count > 1 else { return }
                    selection = 0
                    guard !effectiveReduceMotion else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: UInt64(autoAdvanceInterval * 1_000_000_000))
                        await MainActor.run {
                            let next = (selection + 1) % references.count
                            if effectiveReduceMotion {
                                selection = next
                            } else {
                                withAnimation(.easeInOut(duration: 0.45)) {
                                    selection = next
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
