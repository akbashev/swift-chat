import Hummingbird
import PostgresNIO

struct PostgresConfig {
  
  enum Error: Swift.Error {
    case environmentNotSet
  }
  
  let host: String
  let environment: Environment
  
  func generate() throws -> PostgresConnection.Configuration {
    guard let username = environment.get("DB_USERNAME"),
          let password = environment.get("DB_PASSWORD"),
          let database = environment.get("DB_NAME") else {
      throw PostgresConfig.Error.environmentNotSet
    }
    
    return PostgresConnection.Configuration(
      host: host,
      port: 5432,
      username: username,
      password: password,
      database: database,
      tls: .disable
    )
  }
}
