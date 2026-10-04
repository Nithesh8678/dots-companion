import Foundation

enum LocalServiceError: LocalizedError {
    case permission(String)
    case unavailable(String)
    case unsafeTarget(String)
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .permission(let message), .unavailable(let message), .unsafeTarget(let message), .failed(let message):
            return message
        case .cancelled: return "This operation was cancelled."
        }
    }
}
