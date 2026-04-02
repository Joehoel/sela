import Cocoa

class SaveCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        NotificationCenter.default.post(name: .saveSong, object: nil)
        return nil
    }
}
