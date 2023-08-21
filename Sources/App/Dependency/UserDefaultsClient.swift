import Foundation
import Dependencies

struct UserDefaultsClient {
  
  enum Key: String {
    case userInfo
  }
  
  let boolForKey: (Key) -> Bool
  let dataForKey: (Key) -> Data?
  let doubleForKey: (Key) -> Double
  let integerForKey: (Key) -> Int
  let stringForKey: (Key) -> String?
  let remove: (Key) async -> ()
  let setBool: (Bool, Key) async -> ()
  let setData: (Data?, Key) async -> ()
  let setDouble: (Double, Key) async -> ()
  let setInteger: (Int, Key) async -> ()
  let setString: (String, Key) async -> ()
}

extension UserDefaultsClient: DependencyKey {
  static var liveValue: Self {
    let userDefaults = UserDefaults.standard
    return Self(
      boolForKey: { userDefaults.bool(forKey: $0.rawValue) },
      dataForKey: { userDefaults.data(forKey: $0.rawValue) },
      doubleForKey: { userDefaults.double(forKey: $0.rawValue) },
      integerForKey: { userDefaults.integer(forKey: $0.rawValue) },
      stringForKey: { userDefaults.string(forKey: $0.rawValue) },
      remove: { key in
        userDefaults.removeObject(forKey: key.rawValue)
      },
      setBool: { value, key in
        userDefaults.set(value, forKey: key.rawValue)
      },
      setData: { data, key in
        userDefaults.set(data, forKey: key.rawValue)
      },
      setDouble: { value, key in
        userDefaults.set(value, forKey: key.rawValue)
      },
      setInteger: { value, key in
        userDefaults.set(value, forKey: key.rawValue)
      },
      setString: { value, key in
        userDefaults.set(value, forKey: key.rawValue)
      }
    )
  }
}

extension DependencyValues {
  var userDefaults: UserDefaultsClient {
    get { self[UserDefaultsClient.self] }
    set { self[UserDefaultsClient.self] = newValue }
  }
}
