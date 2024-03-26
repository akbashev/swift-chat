import ArgumentParser
import EventSource

@main
struct EventSourceTest: AsyncParsableCommand {
  
  func run() async throws {
    let store = MemoryEventStore()
    var actor: SomeActor? = try await SomeActor(store: store)
    await print(actor?.get())
    await actor?.save(line: "Test")
    await actor?.save(line: "This")
    await actor?.save(line: "Out")
    await print(actor?.get())
    actor = .none
    try await Task.sleep(for: .seconds(1))
    await actor = try await SomeActor(store: store)
    await print(actor?.get())
    try await Task.sleep(for: .seconds(100_000))
  }
}
