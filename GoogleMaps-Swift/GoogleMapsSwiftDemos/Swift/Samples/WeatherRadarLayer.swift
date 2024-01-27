
//  WeatherRadarLayer.swift
//  Peakbagger
//
//  Created by Andrew Kirmse on 12/8/18.
//  Copyright © 2018 Mountainside. All rights reserved.
//

import Foundation
import GoogleMaps
import UIKit

class WeatherRadarLayer {
    private var tileLayer: GMSTileLayer?
    private var prevTileLayer: GMSTileLayer?
    private var frameNumber = 0
    private var timer: Timer?
    private let dateFormatter = DateFormatter()
    private weak var map: GMSMapView? = nil
    
    // Used for fading out previous layer as new one fades in
    private var displayAnimator: CADisplayLink? = nil
    private var crossfadeStartTime = 0.0
    private let LAYER_UPDATE_DELAY_SECONDS = 2.0
    private let CROSSFADE_TIME = 0.3

    private let LAYER_OPACITY = 0.7

    func enable(map: GMSMapView) {
        self.map = map

        startTimer()
    }

    private func timerCallback() {
        // Remember previous layer to start cross-fading it out
        self.prevTileLayer = self.tileLayer
        
        // Add new layer
        let tileProvider = WeatherRadarTileProvider(frameNumber: self.frameNumber)
        
        tileProvider.opacity = Float(LAYER_OPACITY)
        tileProvider.zIndex = 55
        tileProvider.fadeIn = false
        tileProvider.map = self.map
        self.tileLayer = tileProvider
        
        // Start animation to cross fade
        self.displayAnimator = CADisplayLink(target: self, selector: #selector(crossfadeUpdate))
        self.displayAnimator?.preferredFramesPerSecond = 30
        self.displayAnimator?.add(to: .main, forMode: .default)
        self.crossfadeStartTime = CACurrentMediaTime()

        self.frameNumber += 1
    }
    
    @objc func crossfadeUpdate(displaylink: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = now - self.crossfadeStartTime
        
        let fraction = min(1, dt / CROSSFADE_TIME)
        self.tileLayer?.opacity = Float(LAYER_OPACITY * fraction)
        self.prevTileLayer?.opacity = Float(LAYER_OPACITY * (1 - fraction))
        
        // Animation done?  If so, then done with previous frame of animation
        if dt >= CROSSFADE_TIME {
            self.displayAnimator?.invalidate()
            if let layer = self.prevTileLayer {
                layer.map = nil
            }
            self.prevTileLayer = nil
        }
    }
    
    private func startTimer() {
        if self.timer != nil {
            return
        }
        
        self.timer = Timer.scheduledTimer(withTimeInterval: LAYER_UPDATE_DELAY_SECONDS,
                                          repeats: true) { _ in
            self.timerCallback()
        }
    }
}
