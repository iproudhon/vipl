//
//  AVPlayerController.swift
//  vipl
//
//  Created by Steve H. Jung on 12/21/22.
//

import Foundation
import AVFoundation
import AVKit
import UIKit
import MobileCoreServices

/*
 
Menu Cameras             X
  Set Range
  Save
  Save as New

 ---->----|---<----
Start   Current <Speed>End
Audio Repeat < Play > <> Save

 Save -> folder
 Save as New
 
 square.and.arrow.down -> popup (Save | Save as New Clip)
 quotelevel
 volume.2.fill volume.slash.fill
 */

class AVPlayerController: UIViewController {
    
    // UI components
    private let player = AVPlayer()
    private let dismissButton = UIButton()
    private let playerView = PlayerView()
    private let lowerBoundLabel = UILabel()
    private let currentTimeLabel = UILabel()
    private let upperBoundLabel = UILabel()
    private let stepBackButton = UIButton()
    private let stepForwardButton = UIButton()
    private let playPauseButton = UIButton()
    private let repeatButton = UIButton()
    private let playSpeedMenu = UIButton()
    private let volumeButton = UIButton()
    private let saveButton = UIButton()
    private let rangeSlider = RangeSlider(frame: .zero)
    
    // observers
    private var timeObserverToken: Any?
    private var boundaryTimeObserverToken: Any?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playerItemFastForwardObserver: NSKeyValueObservation?
    private var playerItemReverseObserver: NSKeyValueObservation?
    private var playerItemFastReverseObserver: NSKeyValueObservation?
    private var playerItemControlStatusObserver: NSKeyValueObservation?

    // states
    private var isRepeat = false
    private var playSpeed = Double(1.0)
    
}

extension AVPlayerController {
    private func fmtTime(seconds: Double) -> String {
        var sec = Int(seconds)
        let min = sec / 60
        let cent = Int((seconds - Double(sec)) * 100.0)
        sec = sec % 60
        return String(format: "%02d:%02d:%02d", min, sec, cent)
    }
    
    private func save(asNew: Bool) {
        // TODO: do it
    }
}
