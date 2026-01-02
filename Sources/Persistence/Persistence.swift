import Distributed
import DistributedCluster
import Foundation
import PostgresNIO

protocol Persistable: Sendable {
  func create(input: Persistence.Input) async throws
  func update(input: Persistence.Input) async throws

  func getRoom(for id: UUID) async throws -> RoomModel
  func searchRoom(query: String) async throws -> [RoomModel]

  func getParticipant(for id: UUID) async throws -> ParticipantModel
  func getParticipant(named name: String) async throws -> ParticipantModel
  func getParticipantAuth(named name: String) async throws -> ParticipantAuth
}

public actor Persistence {

  public typealias ActorSystem = ClusterSystem

  public enum `Type`: Sendable {
    case memory
    case postgres(PostgresConnection.Configuration)
  }

  public enum Error: Swift.Error {
    case roomMissing(id: UUID)
    case roomMissing(name: String)
    case participantMissing(id: UUID)
    case participantMissing(name: String)
    case invalidCredentials(name: String)
  }

  public enum Input: Sendable, Codable, Equatable {
    case participant(CreateParticipant)
    case participantUpdate(ParticipantModel)
    case room(RoomModel)
    case roomUpdate(RoomModel)
  }

  private let persistance: any Persistable

  public func create(_ input: Input) async throws {
    try await self.persistance.create(input: input)
  }

  public func update(_ input: Input) async throws {
    try await self.persistance.update(input: input)
  }

  public func getParticipant(for id: UUID) async throws -> ParticipantModel {
    try await self.persistance.getParticipant(for: id)
  }

  public func getParticipant(named name: String) async throws -> ParticipantModel {
    try await self.persistance.getParticipant(named: name)
  }

  public func getParticipantAuth(named name: String) async throws -> ParticipantAuth {
    try await self.persistance.getParticipantAuth(named: name)
  }

  public func getRoom(for id: UUID) async throws -> RoomModel {
    try await self.persistance.getRoom(for: id)
  }

  public func searchRoom(query: String) async throws -> [RoomModel] {
    try await self.persistance.searchRoom(query: query)
  }

  public init(
    type: `Type`
  ) async throws {
    switch type {
    case .memory:
      self.persistance = Cache()
    case .postgres(let configuration):
      self.persistance = try await Postgres(
        configuration: configuration
      )
    }
  }
}
