import AppIntents
import BatteryKit
import Foundation

// The intents the widgets and controls run. They're compiled into the app as well as the widget extension: macOS looks a
// widget button's intent up in the app's App Intents metadata, and won't run one only the extension has ("There is no
// metadata for … in com.pallepadehat.WatchMyBattery"). Whichever runs it, it asks the app, through ``WidgetCommand``,
// as the extension is sandboxed and can't switch Low Power Mode.

/// Turns Low Power Mode on or off, from a widget's button or the Control Center toggle. The extension is sandboxed and
/// can't switch it, so it asks the app (``WidgetCommand``), which does it through its helper.
struct WidgetSetLowPowerModeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Low Power Mode"
    static let description = IntentDescription("Turns Low Power Mode on or off, through WatchMyBattery.")
    static let isDiscoverable = false

    @Parameter(title: "Low Power Mode")
    var value: Bool

    init() {}

    init(value: Bool) {
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        (value ? WidgetCommand.lowPowerModeOn : WidgetCommand.lowPowerModeOff).post()
        // The app takes a moment, then tells WidgetKit to redraw with the new state.
        return .result()
    }
}

/// Opens WatchMyBattery's panel.
@available(macOS 26.0, *)
struct OpenPanelIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Battery Panel"
    static let description = IntentDescription("Opens WatchMyBattery's panel under the menu bar.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "watchmybattery://panel")!))
    }
}
