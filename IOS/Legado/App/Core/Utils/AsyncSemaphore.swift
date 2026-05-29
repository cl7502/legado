// IOS/Legado/App/Core/Utils/AsyncSemaphore.swift
import Foundation

actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ count: Int) { self.count = count }

    func wait() async {
        if count > 0 {
            count -= 1
        } else {
            await withCheckedContinuation { cont in waiters.append(cont) }
        }
    }

    func signal() {
        if waiters.isEmpty {
            count += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
