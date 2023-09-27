//import struct FoundationEssentials.Data
//import NIOCore
//import NIOFoundationCompat
//import PostgresNIO
//
//extension Data: PostgresEncodable {
//    public static var psqlType: PostgresDataType {
//        .bytea
//    }
//
//    public static var psqlFormat: PostgresFormat {
//        .binary
//    }
//
//    @inlinable
//    public func encode<JSONEncoder: PostgresJSONEncoder>(
//        into byteBuffer: inout ByteBuffer,
//        context: PostgresEncodingContext<JSONEncoder>
//    ) {
//        byteBuffer.writeBytes(self)
//    }
//}
//
//extension Data: PostgresDecodable {
//    @inlinable
//    public init<JSONDecoder: PostgresJSONDecoder>(
//        from buffer: inout ByteBuffer,
//        type: PostgresDataType,
//        format: PostgresFormat,
//        context: PostgresDecodingContext<JSONDecoder>
//    ) {
//       let data = buffer.readData(length: buffer.readableBytes, byteTransferStrategy: .automatic)!
//      se/*;*/
//    }
//}
