import AsyncAlgorithms
import Hummingbird
import HummingbirdWebSocket
import Logging
import NIOConcurrencyHelpers
import ServiceLifecycle
import Foundation

public struct ConnectionManager: Service {
  
  typealias OutputStream = AsyncChannel<WebSocketOutboundWriter.OutboundFrame>
  
  public struct Connection: Sendable {
    public struct Info: Hashable, Sendable {
      public let userId: UUID
      public let roomId: UUID
      
      public var description: String {
        "User \(self.userId.uuidString), Room \(self.roomId.uuidString)"
      }
    }
    
    let info: Info
    let inbound: WebSocketInboundStream
    let outbound: OutputStream
  }
  
  actor OutboundConnections {
    
    var outboundWriters: [Connection.Info: OutputStream]

    init() {
      self.outboundWriters = [:]
    }
    
    func send(_ output: WebSocketMessage) async {
      for outbound in self.outboundWriters.values {
        switch output {
        case .text(let string):
          await outbound.send(.text(string))
        case .binary(let byteBuffer):
          await outbound.send(.binary(byteBuffer))
        }
      }
    }
    
    func add(info: Connection.Info, outbound: OutputStream) async {
      self.outboundWriters[info] = outbound
//      await self.send("\(info.userId.uuidString) joined \(info.roomId.uuidString) room")
    }
    
    func remove(info: Connection.Info) async {
      self.outboundWriters[info] = nil
//      await self.send("\(info.userId.uuidString) left \(info.roomId.uuidString) room")
    }
  }
  
  let connectionStream: AsyncStream<Connection>
  let connectionContinuation: AsyncStream<Connection>.Continuation
  let logger: Logger
  
  public init(logger: Logger) {
    self.logger = logger
    (self.connectionStream, self.connectionContinuation) = AsyncStream<Connection>.makeStream()
  }
  
  public func run() async {
    await withGracefulShutdownHandler {
      await withDiscardingTaskGroup { group in
        let outboundCounnections = OutboundConnections()
        for await connection in self.connectionStream {
          group.addTask {
            self.logger.info(
              "add connection",
              metadata: [
                "userId": .string(connection.info.userId.uuidString),
                "roomId": .string(connection.info.roomId.uuidString)
              ]
            )
            await outboundCounnections.add(info: connection.info, outbound: connection.outbound)
            
            do {
              for try await input in connection.inbound.messages(maxSize: 1_000_000) {
                await outboundCounnections.send(input)
              }
            } catch {
              self.logger.log(level: .error, .init(stringLiteral: error.localizedDescription))
            }
            
            self.logger.info(
              "remove connection",
              metadata: [
                "userId": .string(connection.info.userId.uuidString),
                "roomId": .string(connection.info.roomId.uuidString)
              ]
            )
            await outboundCounnections.remove(info: connection.info)
            connection.outbound.finish()
          }
        }
        group.cancelAll()
      }
    } onGracefulShutdown: {
      self.connectionContinuation.finish()
    }
  }
  
  func add(
    info: Connection.Info,
    inbound: WebSocketInboundStream,
    outbound: WebSocketOutboundWriter
  ) -> OutputStream {
    let outputStream = OutputStream()
    let connection = Connection(info: info, inbound: inbound, outbound: outputStream)
    self.connectionContinuation.yield(connection)
    return outputStream
  }
}
