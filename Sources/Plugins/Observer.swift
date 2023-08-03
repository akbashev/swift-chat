/// Quick solution to return values for other subscribers (outer world).
// TODO: Find some right tool for that.
public protocol Observable<Value> {
  associatedtype Value: Sendable
  func subscribe() async throws -> Value
}

public actor Observer<Value> where Value: Sendable {
  
  public enum ObserverError: Error {
    case cancelled
    case limit
  }
  
  private var observers: [CheckedContinuation<Value, any Error>] = []
  private var count: Int = 1
  
  public var value: Value {
    get async throws {
      guard self.observers.count < self.count else { throw ObserverError.limit }
      return try await withCheckedThrowingContinuation(add)
    }
  }

  public func resolve(with result: Result<Value, Error>) {
    self.observers.reversed().forEach { $0.resume(with: result) }
    self.observers.removeAll()
  }
  
  private func add(
    continuation: CheckedContinuation<Value, any Error>
  ) {
    self.observers.append(continuation)
  }
  
  public func cancel() {
    self.resolve(with: .failure(ObserverError.cancelled))
  }
  
  public func isEmpty() -> Bool {
    self.observers.isEmpty
  }
  
  public init(count: Int = 1) {
    self.count = count
  }
  
  deinit {
    Task { await self.cancel() }
  }
}

// TODO: Don't like it, improve
public extension Observable {
  var stream: AsyncStream<Value> {
    .init { continuation in
      let task = Task {
        do {
          while !Task.isCancelled {
            let state = try await self.subscribe()
            continuation.yield(state)
          }
          continuation.finish()
        } catch {
          continuation.finish()
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
