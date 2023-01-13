//
//  RangeSlider.swift
//  vipl
//
//  Created by Steve H. Jung on 12/20/22.
//

import Foundation
import UIKit

class RangeSlider: UIControl {
    enum ActiveControl {
        case thumb
        case lowerBound
        case upperBound
    }
    
    var min: CGFloat = 0 {
        didSet {
            updateLayerFrames()
        }
    }
    var max: CGFloat = 1 {
        didSet {
            updateLayerFrames()
        }
    }
    var lowerBound: CGFloat = 0 {
        didSet {
            updateLayerFrames()
        }
    }
    var upperBound: CGFloat = 1 {
        didSet {
            updateLayerFrames()
        }
    }
    var thumb: CGFloat = 0.5 {
        didSet {
            updateLayerFrames()
        }
    }
    var trackTintColor = UIColor(white: 0.8, alpha: 1) {
        didSet {
            trackLayer.setNeedsDisplay()
        }
    }
    var trackHighlightTintColor = UIColor(red: 0, green: 0.45, blue: 0.94, alpha: 1) {
        didSet {
            trackLayer.setNeedsDisplay()
        }
    }
    
    var rangeOn = false
    var active: ActiveControl = .thumb
    
    private var thumbImage = UIImage(systemName: "poweron")!
    private var lowerBoundImage = UIImage(systemName: "arrowtriangle.down.fill")!
    private var upperBoundImage = UIImage(systemName: "arrowtriangle.up.fill")!
    
    private let trackLayer = RangeSliderTrackLayer()
    private let thumbImageView = UIImageView()
    private let lowerBoundImageView = UIImageView()
    private let upperBoundImageView = UIImageView()
    
    private var previousTouchLocation = CGPoint()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        trackLayer.rangeSlider = self
        trackLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(trackLayer)
          
        lowerBoundImageView.image = lowerBoundImage
        addSubview(lowerBoundImageView)
          
        upperBoundImageView.image = upperBoundImage
        addSubview(upperBoundImageView)
        
        thumbImageView.image = thumbImage
        addSubview(thumbImageView)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        trackLayer.rangeSlider = self
        trackLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(trackLayer)
          
        lowerBoundImageView.image = lowerBoundImage
        addSubview(lowerBoundImageView)
          
        upperBoundImageView.image = upperBoundImage
        addSubview(upperBoundImageView)
        
        thumbImageView.image = thumbImage
        addSubview(thumbImageView)
    }
    
    private func updateLayerFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = bounds.insetBy(dx: 0.0, dy: bounds.height / 3)
        trackLayer.setNeedsDisplay()
        thumbImageView.frame = CGRect(origin: thumbOriginForValue(thumb, thumbImage), size: thumbImage.size)
        lowerBoundImageView.frame = CGRect(origin: thumbOriginForValue(lowerBound, lowerBoundImage), size: lowerBoundImage.size)
        upperBoundImageView.frame = CGRect(origin: thumbOriginForValue(upperBound, upperBoundImage), size: upperBoundImage.size)
        CATransaction.commit()
    }
    
    func positionForValue(_ value: CGFloat) -> CGFloat {
        return bounds.width * value / (max == 0 ? 1 : max)
    }

    private func thumbOriginForValue(_ value: CGFloat, _ img: UIImage) -> CGPoint {
        let x = positionForValue(value) - img.size.width / 2.0
        var y: Double = 0
        if img == thumbImage {
            y = (bounds.height - img.size.height) / 2.0
        } else if img == lowerBoundImage {
            y = 0
        } else if img == upperBoundImage {
            y = (bounds.height - img.size.height)
        }
        return CGPoint(x: x, y: y)
    }
    
    override var frame: CGRect {
        didSet {
            updateLayerFrames()
        }
    }
}

extension RangeSlider {
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        previousTouchLocation = touch.location(in: self)
        if lowerBoundImageView.frame.contains(previousTouchLocation) {
            lowerBoundImageView.isHighlighted = true
            active = .lowerBound
        } else if upperBoundImageView.frame.contains(previousTouchLocation) {
            upperBoundImageView.isHighlighted = true
            active = .upperBound
        } else {
            thumbImageView.isHighlighted = true
            active = .thumb
        }
        return thumbImageView.isHighlighted || lowerBoundImageView.isHighlighted || upperBoundImageView.isHighlighted
    }
    
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let location = touch.location(in: self)
        let deltaLocation = location.x - previousTouchLocation.x
        let deltaValue = (max - min) * deltaLocation / bounds.width
        previousTouchLocation = location
        if thumbImageView.isHighlighted {
            let value = thumb + deltaValue
            thumb = boundValue(value, toLowerValue: lowerBound, upperValue: upperBound)
            active = .thumb
        } else if lowerBoundImageView.isHighlighted {
            let value = lowerBound + deltaValue
            lowerBound = boundValue(value, toLowerValue: min, upperValue: upperBound)
            thumb = boundValue(thumb, toLowerValue: lowerBound, upperValue: upperBound)
            active = .lowerBound
        } else if upperBoundImageView.isHighlighted {
            let value = upperBound + deltaValue
            upperBound = boundValue(value, toLowerValue: lowerBound, upperValue: max)
            thumb = boundValue(thumb, toLowerValue: lowerBound, upperValue: upperBound)
            active = .upperBound
        }
        sendActions(for: .valueChanged)
        return true
    }

    private func boundValue(_ value: CGFloat, toLowerValue lowerValue: CGFloat,
                            upperValue: CGFloat) -> CGFloat {
        return Swift.min(Swift.max(value, lowerValue), upperValue)
    }
    
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        thumbImageView.isHighlighted = false
        lowerBoundImageView.isHighlighted = false
        upperBoundImageView.isHighlighted = false
    }
    
    override func cancelTracking(with event: UIEvent?) {
        thumbImageView.isHighlighted = false
        lowerBoundImageView.isHighlighted = false
        upperBoundImageView.isHighlighted = false
    }
}

// track layer
class RangeSliderTrackLayer: CALayer {
    weak var rangeSlider: RangeSlider?

    override func draw(in ctx: CGContext) {
        guard let slider = rangeSlider else { return }
      
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
        ctx.addPath(path.cgPath)
      
        ctx.setFillColor(slider.trackTintColor.cgColor)
        ctx.fillPath()
      
        ctx.setFillColor(slider.trackHighlightTintColor.cgColor)
        let lowerBoundPosition = slider.positionForValue(slider.lowerBound)
        let upperBoundPosition = slider.positionForValue(slider.upperBound)
        let rect = CGRect(x: lowerBoundPosition, y: 0,
                          width: upperBoundPosition - lowerBoundPosition,
                          height: bounds.height)
        ctx.fill(rect)
    }
}
