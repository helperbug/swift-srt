enum SrtListenerStates {
    case induced
    case inductionResponding
    case inducted
    case conclusionResponding
    case active
    case shutdown
    case error

    var label: String {
        switch self {
        case .induced:
            return "Induced"
        case .inductionResponding:
            return "Induction Responding"
        case .inducted:
            return "Inducted"
        case .conclusionResponding:
            return "Conclusion Responding"
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
        case .induced:
            return "Blue"
        case .inductionResponding:
            return "Orange"
        case .inducted:
            return "Green"
        case .conclusionResponding:
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
        case .induced:
            return "arrow.right.circle"
        case .inductionResponding:
            return "arrow.triangle.2.circlepath"
        case .inducted:
            return "checkmark.circle"
        case .conclusionResponding:
            return "paperplane.circle"
        case .active:
            return "waveform.circle"
        case .shutdown:
            return "power.circle"
        case .error:
            return "xmark.octagon"
        }
    }
    
    var instance: SrtListenerState {
        switch self {
        case .induced:
            return StrListenerInducedState()
        case .inductionResponding:
            return SrtListenerInductionRespondingState()
        case .inducted:
            return StrListenerInductedState()
        case .conclusionResponding:
            return SrtListenerConclusionRespondingState()
        case .active:
            return SrtListenerActiveState()
        case .shutdown:
            return SrtListenerShutdownState()
        case .error:
            return SrtListenerErrorStateState()
        }
    }
    
}
