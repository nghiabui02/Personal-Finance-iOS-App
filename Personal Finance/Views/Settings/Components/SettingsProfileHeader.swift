import SwiftUI
import PhotosUI

struct SettingsProfileHeader: View {
    let avatarURL: URL?
    let displayName: String
    let email: String
    let isUpdating: Bool
    @Binding var photoItem: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 16) {
            AvatarView(url: avatarURL, size: 64)
                .overlay(alignment: .bottomTrailing) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white, Color.blue)
                            .background(Circle().fill(Color(.systemBackground)).padding(2))
                    }
                    .buttonStyle(.plain)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                Text(email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isUpdating {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.vertical, 6)
    }
}
