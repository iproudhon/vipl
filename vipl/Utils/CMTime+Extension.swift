//
//  CMTime+Extension.swift
//  vipl
//

import AVFoundation

extension CMTime {
    func toDurationString(withSubSeconds: Bool = false) -> String {
        var sec = Int(self.seconds)
        var min = sec / 60
        let hours = min / 60
        let cent = Int((self.seconds - Double(Float(sec))) * 100.0)
        min = min % 60
        sec = sec % 60

        var out = ""
        if hours > 0 {
            out += String(format: "%d:%02d:", hours, min)
        } else if min > 0 {
            out += String(format: "%d:%02d", min, sec)
        } else {
            out += String(format: "%d", sec)
        }
        if withSubSeconds {
            out += String(format: ":%02d", cent)
        }
        return out
    }

    func msec() -> Int {
        return Int(seconds * 1000)
    }

    func equalInMsec(seconds: Double) -> Bool {
        return Int(self.seconds * 1000) == Int(seconds * 1000)
    }
}

extension Double {
    func equalInMsec(to: Double) -> Bool {
        return Int(self * 1000) == Int(to * 1000)
    }
}
