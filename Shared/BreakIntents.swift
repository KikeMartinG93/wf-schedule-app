import AppIntents

/// The Start button on the Lock Screen. A `LiveActivityIntent` runs in the app's
/// process (launched in the background if need be), which is what lets a tap start
/// a timer and schedule its alarm without opening the app.
struct StartBreakIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start break"
    /// The whole point is a tap on the Lock Screen, so it can't ask for Face ID first.
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Break", default: 0)
    var stage: Int

    init() {}

    init(stage: Int) {
        self.stage = stage
    }

    func perform() async throws -> some IntentResult {
        await BreakFlowEngine.startBreak(stage: stage)
        return .result()
    }
}

/// The alarm's Stop button.
struct FinishBreakIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Finish break"
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Break", default: 0)
    var stage: Int

    init() {}

    init(stage: Int) {
        self.stage = stage
    }

    func perform() async throws -> some IntentResult {
        await BreakFlowEngine.finishBreak(stage: stage)
        return .result()
    }
}
