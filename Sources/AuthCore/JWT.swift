import CryptoKit
import Foundation

public struct JWTSigner: Sendable {
  public enum Error: Swift.Error {
    case invalidToken
    case invalidIssuer
    case expired
  }

  private struct Header: Codable {
    let alg: String
    let typ: String
  }

  public let secret: Data
  public let issuer: String
  public let ttlSeconds: Int

  public init(secret: Data, issuer: String, ttlSeconds: Int) {
    self.secret = secret
    self.issuer = issuer
    self.ttlSeconds = ttlSeconds
  }

  public func sign(subject: String, now: Date = Date()) throws -> String {
    let issuedAt = Int(now.timeIntervalSince1970)
    let expiresAt = issuedAt + ttlSeconds
    let header = Header(alg: "HS256", typ: "JWT")
    let claims = JWTClaims(sub: subject, iss: issuer, iat: issuedAt, exp: expiresAt)
    let encoder = JSONEncoder()
    let headerPart = Self.base64URLEncode(try encoder.encode(header))
    let payloadPart = Self.base64URLEncode(try encoder.encode(claims))
    let signingInput = "\(headerPart).\(payloadPart)"
    let signature = Self.sign(signingInput: signingInput, secret: secret)
    return "\(signingInput).\(signature)"
  }

  public func verify(token: String, now: Date = Date()) throws -> JWTClaims {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { throw Error.invalidToken }

    let headerData = try Self.decodeBase64URL(String(parts[0]))
    let payloadData = try Self.decodeBase64URL(String(parts[1]))
    let signature = String(parts[2])
    let signingInput = "\(parts[0]).\(parts[1])"
    let expectedSignature = Self.sign(signingInput: signingInput, secret: secret)
    guard constantTimeEquals(signature, expectedSignature) else { throw Error.invalidToken }

    let decoder = JSONDecoder()
    let header = try decoder.decode(Header.self, from: headerData)
    guard header.alg == "HS256" else { throw Error.invalidToken }

    let claims = try decoder.decode(JWTClaims.self, from: payloadData)
    guard claims.iss == issuer else { throw Error.invalidIssuer }
    let nowSeconds = Int(now.timeIntervalSince1970)
    guard claims.exp > nowSeconds else { throw Error.expired }
    return claims
  }

  private static func sign(signingInput: String, secret: Data) -> String {
    let key = SymmetricKey(data: secret)
    let signature = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: key)
    return base64URLEncode(Data(signature))
  }

  private static func decodeBase64URL(_ value: String) throws -> Data {
    guard let data = base64URLDecode(value) else { throw Error.invalidToken }
    return data
  }

  private static func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private static func base64URLDecode(_ value: String) -> Data? {
    var base64 =
      value
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let padding = 4 - (base64.count % 4)
    if padding < 4 {
      base64 += String(repeating: "=", count: padding)
    }
    return Data(base64Encoded: base64)
  }

  private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
    guard lhs.count == rhs.count else { return false }
    var result: UInt8 = 0
    for (left, right) in zip(lhs.utf8, rhs.utf8) {
      result |= left ^ right
    }
    return result == 0
  }
}

public struct JWTClaims: Codable, Sendable {
  public let sub: String
  public let iss: String
  public let iat: Int
  public let exp: Int
}
