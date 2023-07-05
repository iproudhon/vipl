//
//  PlayerViewController+Gesture.swift
//  vipl
//
//  Created by Steve H. Jung on 1/14/23.
//

import AVFoundation
import UIKit

extension PlayerViewController {
    // add tap & pan gestures
    func addGestures() {
        playerView.controller = self

        let tap = UITapGestureRecognizer(target: playerView, action: #selector(playerView.tap(_:)))
        tap.numberOfTouchesRequired = 1
        playerView.addGestureRecognizer(tap)

#if false
        let longHold = UILongPressGestureRecognizer(target: self.playerView, action: #selector(playerView.longHold(_:)))
        longHold.numberOfTouchesRequired = 1
        playerView.addGestureRecognizer(longHold)
#endif

        let pan = UIPanGestureRecognizer(target: self.playerView, action: #selector(playerView.pan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        playerView.addGestureRecognizer(pan)
    }

    @objc public func tap(_ sender: UITapGestureRecognizer) {
        guard let view = sender.view,
              let superview = view.superview?.superview as? UIScrollView else { return }
        let rect = superview.convert(superview.bounds, to: view)
        let size = CGSize(width: rect.width, height: rect.height)
        var pt = sender.location(in: view)
        pt.x -= rect.minX
        pt.y -= rect.minY

        if size.width * 2 / 5 <=  pt.x && pt.x <= size.width * 3 / 5 && size.height * 2 / 5 <=  pt.y && pt.y <= size.height * 3 / 5 {
            togglePlay(1)
        } else if pt.x <= size.width * 2 / 5 {
            stepBack(1)
        } else if pt.x >= size.width * 3 / 5 {
            stepForward(1)
        }
    }

    // TODO: unused for now
    @objc public func longHold(_ sender: UILongPressGestureRecognizer) {
        switch (sender.state) {
        case .began:
            print("began")
        case .changed:
            print("changed")
        case .ended:
            print("ended")
        case .failed, .cancelled:
            print("failed or canceled")
        default:
            print("other")
        }
    }

    @objc public func pan(_ sender: UIPanGestureRecognizer) {
        guard let view = sender.view else { return }
        let pt = sender.location(in: view)

        switch sender.state {
        case .began:
            panPoint = pt
            panStartTime = player.currentTime()
        case .changed:
            guard let opt = panPoint, let ot = panStartTime else { return }
            var dx = pt.x - opt.x
            dx = (dx / 500) * 1.0
            dx += ot.seconds
            dx = max(min(dx, player.currentItem?.duration.seconds ?? 0), 0)
            smoothSeek(to: CMTime(seconds: dx, preferredTimescale: 600), completionHandler: { _ in })
        default:
            break
        }
    }
}
