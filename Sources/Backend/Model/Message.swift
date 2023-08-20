public enum Message: Sendable, Codable, Equatable {
  case join
  case message(String)
  case leave
  case disconnect
}
