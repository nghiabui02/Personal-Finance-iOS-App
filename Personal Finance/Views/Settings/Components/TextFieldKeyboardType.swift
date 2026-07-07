import UIKit

enum TextFieldKeyboardType: Equatable {
    case `default`
    case email
    case phonePad

    var swiftUIKeyboardType: UIKeyboardType {
        switch self {
        case .default:
            return .default
        case .email:
            return .emailAddress
        case .phonePad:
            return .phonePad
        }
    }
}
