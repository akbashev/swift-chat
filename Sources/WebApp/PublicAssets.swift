import Foundation

public enum WebAppAssets {
  public static var publicRoot: String {
    Bundle.module.resourceURL!.appendingPathComponent("Public").path
  }
}
