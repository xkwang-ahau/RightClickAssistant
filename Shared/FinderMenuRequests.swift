import Foundation

nonisolated struct FinderMenuRequests {
    private var nextTag = 1
    private var requests: [Int: URL] = [:]
    private let capacity: Int

    init(capacity: Int = 512) {
        self.capacity = max(1, capacity)
    }

    mutating func store(_ url: URL) -> Int {
        let tag = nextTag
        nextTag += 1
        requests[tag] = url
        requests.removeValue(forKey: tag - capacity)
        return tag
    }

    func url(for tag: Int) -> URL? { requests[tag] }
}
