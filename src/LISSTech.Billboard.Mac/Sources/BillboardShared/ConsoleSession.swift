import Darwin
import Foundation
import SystemConfiguration

public struct ConsoleUserSession: Sendable {
    public let name: String
    public let uid: uid_t
    public let gid: gid_t
    public let home: String
}

public enum ConsoleSession {
    public static func activeUser() throws -> ConsoleUserSession {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard let value = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?,
              !value.isEmpty,
              value != "loginwindow",
              value != "_mbsetupuser",
              uid >= 500,
              let record = getpwuid(uid) else {
            throw BillboardError.transport("No interactive macOS console user is logged in.")
        }
        return ConsoleUserSession(
            name: value,
            uid: uid,
            gid: gid,
            home: String(cString: record.pointee.pw_dir))
    }
}
