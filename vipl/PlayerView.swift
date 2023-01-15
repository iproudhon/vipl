//
//  PlayerView.swift
//  vipl
//
//  Created by Steve H. Jung on 12/12/22.
//

import UIKit
import AVFoundation

class PlayerView: UIView {
    var controller: PlayerViewController?
    
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    @objc func tap(_ sender: UITapGestureRecognizer) {
        controller?.tap(sender)
    }

    @objc func longHold(_ sender: UILongPressGestureRecognizer) {
        controller?.longHold(sender)
    }

    @objc func pan(_ sender: UIPanGestureRecognizer) {
        controller?.pan(sender)
    }
}
