import ServiceManagement

enum LoginItemState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

protocol LoginItemManaging {
    var state: LoginItemState { get }
    func register() throws
    func unregister(completion: @escaping (Error?) -> Void)
}

final class SystemLoginItemManager: LoginItemManaging {
    private let service = SMAppService.mainApp

    var state: LoginItemState {
        switch service.status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister(completion: @escaping (Error?) -> Void) {
        service.unregister(completionHandler: completion)
    }
}
