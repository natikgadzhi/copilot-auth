/// AppKit injects launch options like `-NSDocumentRevisionsDebugMode YES` on a
/// GUI launch (and on a Finder double-click). Strip them — and their values — so
/// ArgumentParser sees only the user's real arguments. Pure, so it's testable
/// without launching anything.
public enum LaunchArguments {
  public static func user(from raw: [String]) -> [String] {
    var result: [String] = []
    var iterator = raw.makeIterator()
    while let arg = iterator.next() {
      if arg.hasPrefix("-NS") || arg.hasPrefix("-Apple") {
        _ = iterator.next()  // skip the injected option's value
        continue
      }
      result.append(arg)
    }
    return result
  }
}
