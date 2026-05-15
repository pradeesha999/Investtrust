import AVFoundation
import FirebaseStorage
import SwiftUI

// Plays opportunity pitch videos from Firebase Storage or Cloudinary URLs
// Uses AVPlayerLayer so video renders correctly inside scroll views
struct StorageBackedVideoPlayer: View {
    let reference: String
    var height: CGFloat = 200
    var cornerRadius: CGFloat = 16
    var muted: Bool = true
    // Reserved for future custom chrome; inline playback uses a layer (no system scrubber).
    var showsPlaybackControls: Bool = false
    var allowFullscreenOnTap: Bool = false
    var fullscreenPlaysMuted: Bool = false
    var onLoadFailed: (() -> Void)?

    @State private var player: AVPlayer?
    @State private var loadFailed = false
    @State private var failureReason: String?
    @State private var resolvedPlaybackURL: URL?
    @State private var fullscreenPresented = false

    private static let urlCache: NSCache<NSString, NSURL> = {
        let c = NSCache<NSString, NSURL>()
        c.countLimit = 32
        return c
    }()

    static func clearURLCache() {
        urlCache.removeAllObjects()
    }

    var body: some View {
        ZStack {
            if let player {
                InlineAVPlayerLayerView(
                    player: player,
                    videoGravity: .resizeAspectFill
                )
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    if allowFullscreenOnTap && !showsPlaybackControls {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.black.opacity(0.001))
                            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                            .onTapGesture {
                                player.pause()
                                fullscreenPresented = true
                            }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if allowFullscreenOnTap {
                        Button {
                            player.pause()
                            fullscreenPresented = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .padding(10)
                    }
                }
                .onAppear {
                    player.play()
                }
            } else if loadFailed {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay {
                        VStack(spacing: 8) {
                            Label("Video unavailable", systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let failureReason {
                                Text(failureReason)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.systemGray6))
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: reference) { await setupPlayer() }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .fullScreenCover(isPresented: $fullscreenPresented) {
            Group {
                if let url = resolvedPlaybackURL {
                    FullscreenVideoPlayer(url: url, muted: fullscreenPlaysMuted)
                } else {
                    Color.black
                        .onAppear { fullscreenPresented = false }
                }
            }
        }
        .onChange(of: fullscreenPresented) { _, isOpen in
            if !isOpen {
                player?.isMuted = muted
                player?.play()
            }
        }
    }

    private func setupPlayer() async {
        await MainActor.run {
            loadFailed = false
            failureReason = nil
            resolvedPlaybackURL = nil
            player?.pause()
            player = nil
        }

        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await markFailed("Missing video reference.")
            return
        }

        guard let remoteURL = await resolvePlaybackURL(from: trimmed) else {
            let reason = await MainActor.run {
                failureReason ?? "Could not get a playable URL. Sign in, check Storage rules, and ensure videoURL or videoStoragePath is set in Firestore."
            }
            await markFailed(reason)
            return
        }

        let playbackURL: URL
        if remoteURL.scheme == "http" || remoteURL.scheme == "https" {
            playbackURL = (try? await SessionMediaCache.shared.materializeRemoteFile(at: remoteURL)) ?? remoteURL
        } else {
            playbackURL = remoteURL
        }

        await MainActor.run {
            resolvedPlaybackURL = playbackURL
        }

        let asset = AVURLAsset(url: playbackURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = playbackURL.isFileURL ? 3 : 12

        let ready = await waitForPlayerItemReady(item, timeoutSeconds: 25)
        if !ready {
            let err = item.error?.localizedDescription ?? "Video failed to load."
            await markFailed(err)
            return
        }

        await MainActor.run {
            let p = AVPlayer(playerItem: item)
            p.isMuted = muted
            p.automaticallyWaitsToMinimizeStalling = true
            player = p
            p.play()
        }
    }

    // Waits until the item is ready or definitively failed (avoids an “invisible” player stuck in `.unknown`).
    private func waitForPlayerItemReady(_ item: AVPlayerItem, timeoutSeconds: TimeInterval) async -> Bool {
        if item.status == .readyToPlay { return true }
        if item.status == .failed { return false }

        return await withCheckedContinuation { continuation in
            var finished = false
            var observation: NSKeyValueObservation?
            var timeoutTask: Task<Void, Never>?

            func finish(_ ok: Bool) {
                guard !finished else { return }
                finished = true
                observation?.invalidate()
                observation = nil
                timeoutTask?.cancel()
                timeoutTask = nil
                continuation.resume(returning: ok)
            }

            observation = item.observe(\.status, options: [.new]) { observed, _ in
                switch observed.status {
                case .readyToPlay:
                    finish(true)
                case .failed:
                    finish(false)
                default:
                    break
                }
            }

            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                if item.status == .readyToPlay {
                    finish(true)
                } else if item.status == .failed {
                    finish(false)
                } else {
                    // Still `.unknown` — many remote URLs become playable only after `play()`; keep trying.
                    finish(true)
                }
            }
        }
    }

    private func markFailed(_ reason: String) async {
        await MainActor.run {
            loadFailed = true
            failureReason = reason
            player = nil
            resolvedPlaybackURL = nil
            onLoadFailed?()
        }
    }

    private func resolvePlaybackURL(from trimmed: String) async -> URL? {
        if let cached = Self.urlCache.object(forKey: trimmed as NSString) {
            return cached as URL
        }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            guard let url = URL(string: trimmed) else {
                await MainActor.run { failureReason = "Invalid video URL." }
                return nil
            }
            Self.urlCache.setObject(url as NSURL, forKey: trimmed as NSString)
            return url
        }

        if trimmed.hasPrefix("gs://") {
            let ref = Storage.storage().reference(forURL: trimmed)
            do {
                let url = try await ref.downloadURL()
                Self.urlCache.setObject(url as NSURL, forKey: trimmed as NSString)
                return url
            } catch {
                await MainActor.run { failureReason = error.localizedDescription }
                return nil
            }
        }

        let path = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        let ref = Storage.storage().reference(withPath: path)
        do {
            let url = try await ref.downloadURL()
            Self.urlCache.setObject(url as NSURL, forKey: trimmed as NSString)
            return url
        } catch {
            await MainActor.run { failureReason = error.localizedDescription }
            return nil
        }
    }
}
