import Cocoa

class FixAllCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        NotificationCenter.default.post(name: .fixAllIssues, object: nil)
        return nil
    }
}
