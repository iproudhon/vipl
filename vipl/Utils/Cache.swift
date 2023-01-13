//
//  cache.swift
//  vipl
//
//  Created by Steve H. Jung on 1/1/23.
//

import Foundation

class Cache {
    static let Default = Cache()

    let cache = NSCache<NSString, NSObject>()

    class Entry: NSObject {
        let value: Any
        init(_ value: Any) { self.value = value }
    }

    init() {
        self.cache.countLimit = 240 * 60
    }

    func get(_ key: String) -> Any? {
        guard let obj = self.cache.object(forKey: key as NSString),
              let entry = obj as? Entry else {
            return nil
        }
        return entry.value
    }

    func set(_ key: String, _ value: Any) {
        self.cache.setObject(Entry(value), forKey: key as NSString)
    }

    func del(_ key: String) {
        self.cache.removeObject(forKey: key as NSString)
    }
}
