import AVFoundation
import AVKit
import SwiftUI

// Full-screen video player with a dismiss button.
// Uses AVPlayerViewController for reliable layout and caches the download via SessionMediaCache.
struct FullscreenVideoPlayer: View {
    let url: URL
    var muted: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let player {
                AVPlayerViewControllerSwiftUI(
                    player: player,
                    showsPlaybackControls: true,
                    videoGravity: .resizeAspect
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            Button {
                player?.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.45))
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
            .accessibilityLabel("Close video")
        }
        .task(id: url.absoluteString) {
            await prepareAndPlay()
        }
        .onDisappear {
            player?.pause()
            player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func prepareAndPlay() async {
        let playURL: URL
        if url.isFileURL {
            playURL = url
        } else if url.scheme == "http" || url.scheme == "https" {
            playURL = (try? await SessionMediaCache.shared.materializeRemoteFile(at: url)) ?? url
        } else {
            playURL = url
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)

        let asset = AVURLAsset(url: playURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = playURL.isFileURL ? 3 : 12

        let p = AVPlayer(playerItem: item)
        p.isMuted = muted
        p.play()

        await MainActor.run {
            player = p
        }
    }
}
