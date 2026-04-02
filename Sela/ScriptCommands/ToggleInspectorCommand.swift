import Cocoa

class ToggleInspectorCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DispatchQueue.main.async {
            SelaApp.shared?.isInspectorPresented.toggle()
        }
        return nil
    }
}
