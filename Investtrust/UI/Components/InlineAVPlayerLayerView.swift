import AVFoundation
import SwiftUI
import UIKit

// AVPlayerLayer-based inline video view that renders correctly inside scroll views
// (AVPlayerViewController inside UIViewControllerRepresentable breaks in ScrollView/LazyVStack)
struct InlineAVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerHostingView {
        let v = PlayerHostingView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = videoGravity
        v.playerLayer.backgroundColor = UIColor.black.cgColor
        return v
    }

    func updateUIView(_ uiView: PlayerHostingView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = videoGravity
    }

    // The view’s backing layer is the `AVPlayerLayer`, so it always sizes with the SwiftUI frame.
    final class PlayerHostingView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            clipsToBounds = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }
    }
}
