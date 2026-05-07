import AVKit
import SwiftUI
import UIKit

/// UIKit-backed player — SwiftUI `VideoPlayer` often renders a grey frame in scroll views / `LazyVStack`.
struct AVPlayerViewControllerSwiftUI: UIViewControllerRepresentable {
    let player: AVPlayer
    var showsPlaybackControls: Bool
    var videoGravity: AVLayerVideoGravity

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = showsPlaybackControls
        vc.videoGravity = videoGravity
        vc.view.backgroundColor = .black
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
        uiViewController.showsPlaybackControls = showsPlaybackControls
        uiViewController.videoGravity = videoGravity
    }
}
