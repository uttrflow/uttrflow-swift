import Foundation

/// How an error is written to the unified log: its type and case, never its payload.
public enum ErrorLog {
    /// An error's type and case, without the payload, which may hold text a person typed, said or read.
    public static func failure(_ error: any Error) -> String {
        let type = String(describing: Swift.type(of: error))
        let mirror = Mirror(reflecting: error)
        if mirror.displayStyle == .enum {
            // A case with a payload is one labelled child; a case without one has no children and describes itself.
            guard let label = mirror.children.first?.label else {
                return "\(type).\(String(describing: error))"
            }
            return "\(type).\(label)"
        }
        let bridged = error as NSError
        return "\(type) domain=\(bridged.domain) code=\(bridged.code)"
    }
}
