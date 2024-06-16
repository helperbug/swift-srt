enum SrtCallerStates {
    case start
    case inductionRequesting
    case inducted
    case conclusionRequesting
    case active
    case shutdown
    case error

    var label: String {
        switch self {
        case .start:
            return "Start"
        case .inductionRequesting:
            return "Induction Requesting"
        case .inducted:
            return "Inducted"
        case .conclusionRequesting:
            return "Conclusion Requesting"
        case .active:
            return "Active"
        case .shutdown:
            return "Shutdown"
        case .error:
            return "Error"
        }
    }

    var color: String {
        switch self {
        case .start:
            return "Blue"
        case .inductionRequesting:
            return "Orange"
        case .inducted:
            return "Green"
        case .conclusionRequesting:
            return "Yellow"
        case .active:
            return "Green"
        case .shutdown:
            return "Red"
        case .error:
            return "Red"
        }
    }

    var symbol: String {
        switch self {
        case .start:
            return "arrow.right.circle"
        case .inductionRequesting:
            return "arrow.triangle.2.circlepath"
        case .inducted:
            return "checkmark.circle"
        case .conclusionRequesting:
            return "paperplane.circle"
        case .active:
            return "waveform.circle"
        case .shutdown:
            return "power.circle"
        case .error:
            return "xmark.octagon"
        }
    }
    
    var instance: SrtCallerState {
        switch self {
        case .start:
            return StrCallerStartState()
        case .inductionRequesting:
            return SrtCallerInductionRequestingState()
        case .inducted:
            return StrCallerInductedState()
        case .conclusionRequesting:
            return SrtCallerConclusionRequestingState()
        case .active:
            return SrtCallerActiveState()
        case .shutdown:
            return SrtCallerShutdownState()
        case .error:
            return SrtCallerErrorStateState()
        }
    }
    
}
