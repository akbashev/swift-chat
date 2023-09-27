import NIOCore
import FoundationEssentials
import struct FoundationEssentials.UUID
import typealias FoundationEssentials.uuid_t
import PostgresNIO
import NIOFoundationCompat

extension FoundationEssentials.UUID: PostgresNonThrowingEncodable {
  public static var psqlType: PostgresDataType {
    .uuid
  }
  
  public static var psqlFormat: PostgresFormat {
    .binary
  }
  
  @inlinable
  public func encode<JSONEncoder: PostgresJSONEncoder>(
    into byteBuffer: inout ByteBuffer,
    context: PostgresEncodingContext<JSONEncoder>
  ) {
    byteBuffer.writeUUIDBytes(.init(uuid: self.uuid))
  }
}

extension FoundationEssentials.UUID: PostgresDecodable {
  @inlinable
  public init<JSONDecoder: PostgresJSONDecoder>(
    from buffer: inout ByteBuffer,
    type: PostgresDataType,
    format: PostgresFormat,
    context: PostgresDecodingContext<JSONDecoder>
  ) throws {
    switch (format, type) {
    case (.binary, .uuid):
      guard let uuid = buffer.readUUIDBytes() else {
        throw PostgresDecodingError.Code.failure
      }
      self = .init(uuid: uuid.uuid)
    case (.binary, .varchar),
      (.binary, .text),
      (.text, .uuid),
      (.text, .text),
      (.text, .varchar):
      guard buffer.readableBytes == 36 else {
        throw PostgresDecodingError.Code.failure
      }
      
      guard let uuid = buffer.readString(length: 36).flatMap({ UUID(uuidString: $0) }) else {
        throw PostgresDecodingError.Code.failure
      }
      self = uuid
    default:
      throw PostgresDecodingError.Code.typeMismatch
    }
  }
}
