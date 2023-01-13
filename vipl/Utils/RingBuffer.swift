//
//  RingBuffer.swift
//  vipl
//

import Foundation

struct RingBuffer<T> {
    private var elements: [T?]
    private var head: Int = -1
    private var tail: Int = -1

    init(count: Int) {
        elements = Array(repeating: nil, count: count)
    }

    var count: Int {
        if isEmpty {
            return 0
        } else if tail < head {
            return tail + elements.count - head + 1
        } else {
            return tail - head + 1
        }
    }

    var isEmpty: Bool {
        return head == -1 && tail == -1
    }

    var isFull: Bool {
        return (tail + 1) % elements.count == head
    }

    var front: T? {
        return head == -1 ? nil : elements[head]
    }

    var rear: T? {
        return tail == -1 ? nil : elements[tail]
    }

    func get(_ nth: Int) -> T? {
        if isEmpty || nth < 0 {
            return nil
        }
        let nth = self.head + nth
        let tail = self.tail >= self.head ? tail : (self.tail + elements.count)
        if nth > tail {
            return nil
        }
        return elements[nth % elements.count]
    }

    mutating func clear() {
        head = -1
        tail = -1
        elements = Array(repeating: nil, count: elements.count)
    }

    mutating func prepend(_ item: T, overwrite: Bool = false) -> Bool {
        if head == -1 {
            head = 0
            tail = 0
            elements[head] = item
            return true
        }
        let ix = (head + elements.count - 1) % elements.count
        if overwrite == false && ix == tail {
            return false
        }
        head = ix
        elements[head] = item
        if head == tail {
            tail = (head + elements.count - 1) % elements.count
        }
        return true
    }

    mutating func append(_ item: T, overwrite: Bool = false) -> Bool {
        if head == -1 {
            head = 0
            tail = 0
            elements[head] = item
            return true
        }
        let ix = (tail + 1) % elements.count
        if overwrite == false && ix == head {
            return false
        }
        tail = ix
        elements[tail] = item
        if head == tail {
            head = (tail + 1) % elements.count
        }
        return true
    }

    mutating func popFront() -> T? {
        if head == -1 {
            return nil
        }
        let t = elements[head]
        elements[head] = nil
        if head == tail {
            head = -1
            tail = -1
        } else {
            head = (head + 1) % elements.count
        }
        return t
    }

    mutating func popBack() -> T? {
        if tail == -1 {
            return nil
        }
        let t = elements[tail]
        elements[tail] = nil
        if head == tail {
            head = -1
            tail = -1
        } else {
            tail = (tail + 1) % elements.count
        }
        return t
    }
}
