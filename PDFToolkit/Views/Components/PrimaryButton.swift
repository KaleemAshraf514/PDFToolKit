import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(isDisabled ? AppTheme.blue.opacity(0.45) : AppTheme.blue)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
