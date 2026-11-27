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

    /// Lets iOS offer the matching value from the person's contact card.
    var textContentType: UITextContentType {
        switch self {
        case .default:
            return .name
        case .email:
            return .emailAddress
        case .phonePad:
            return .telephoneNumber
        }
    }
}
