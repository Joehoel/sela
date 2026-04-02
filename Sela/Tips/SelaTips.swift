import SwiftUI
import TipKit

struct DiagnoseInspectorTip: Tip {
    var title: Text {
        Text("Check Translation Quality")
    }

    var message: Text? {
        Text("Open the diagnose panel to find and fix issues in your translations.")
    }

    var image: Image? {
        Image(systemName: "stethoscope")
    }
}

struct ChangeEngineTip: Tip {
    var title: Text {
        Text("Switch Translation Engine")
    }

    var message: Text? {
        Text("Choose between Google Translate, MyMemory, DeepL, and more in Settings.")
    }

    var image: Image? {
        Image(systemName: "gear")
    }
}
