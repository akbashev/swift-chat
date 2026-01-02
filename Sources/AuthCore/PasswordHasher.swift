import HummingbirdBcrypt
import NIOPosix

public enum PasswordHasher {
  public static func hash(_ password: String) async throws -> String {
    try await NIOThreadPool.singleton.runIfActive {
      Bcrypt.hash(password)
    }
  }

  public static func verify(_ password: String, hash: String) async throws -> Bool {
    try await NIOThreadPool.singleton.runIfActive {
      Bcrypt.verify(password, hash: hash)
    }
  }
}
