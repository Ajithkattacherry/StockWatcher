/// Hands out evenly spaced time slots. The slot is reserved before sleeping,
/// so concurrent callers never share one.
public actor RateLimiter {
    private let interval: Duration
    private let clock = ContinuousClock()
    private var nextSlot: ContinuousClock.Instant

    public init(requestsPerSecond: Double) {
        let nanos = Int64((1_000_000_000 / requestsPerSecond).rounded())
        interval = .nanoseconds(nanos)
        nextSlot = clock.now
    }

    public func acquire() async {
        let now = clock.now
        let slot = max(now, nextSlot)
        nextSlot = slot + interval
        if slot > now {
            try? await Task.sleep(until: slot, clock: clock)
        }
    }
}
