// Development helper: drives the running Debug build without synthesizing key events.
//   swift Scripts/debug-command.swift toggle|show|hide|status|retention|snapshot [path]|pin-first|filter <Kind>|select-right|select-left|confirm
// The app only listens for these in Debug builds.
import Foundation

let command = CommandLine.arguments.dropFirst().first ?? "status"
var userInfo: [AnyHashable: Any] = ["command": command]
if let argument = CommandLine.arguments.dropFirst(2).first { userInfo["argument"] = argument }
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("dev.armaan.ClipboardManager.debug"),
    object: command,
    userInfo: userInfo,
    deliverImmediately: true
)
