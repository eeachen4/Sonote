import SwiftUI

// MARK: - Minimalist Adaptive Setting Card & Reusable Controls

struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textMuted)
                }
            }
            .padding(.leading, 2)

            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.elevatedSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.015), radius: 4, y: 1)
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AppTheme.brandPrimary)
        }
    }
}

struct CleanInputBox: View {
    let placeholder: String
    @Binding var text: String
    var onSubmitAction: (() -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var isHovering: Bool = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(AppTheme.textPrimary)
            .multilineTextAlignment(.leading)
            .focused($isFocused)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? AppTheme.brandPrimary
                            : (isHovering ? AppTheme.inputHoverBorder : AppTheme.inputBorder),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .shadow(
                color: isFocused ? AppTheme.brandPrimary.opacity(0.18) : Color.black.opacity(0.02),
                radius: isFocused ? 4 : 1,
                y: isFocused ? 0 : 0.5
            )
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
            .onSubmit { onSubmitAction?() }
    }
}

struct CleanSecureBox: View {
    let placeholder: String
    @Binding var text: String

    @FocusState private var isFocused: Bool
    @State private var isHovering: Bool = false
    @State private var isRevealed: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(AppTheme.textPrimary)
            .multilineTextAlignment(.leading)
            .focused($isFocused)

            if !text.isEmpty {
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.textMuted)
                        .frame(width: 20, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isRevealed ? L("隐藏密钥", "Hide Secret") : L("显示密钥", "Show Secret"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isFocused
                        ? AppTheme.brandPrimary
                        : (isHovering ? AppTheme.inputHoverBorder : AppTheme.inputBorder),
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .shadow(
            color: isFocused ? AppTheme.brandPrimary.opacity(0.18) : Color.black.opacity(0.02),
            radius: isFocused ? 4 : 1,
            y: isFocused ? 0 : 0.5
        )
        .animation(.easeOut(duration: 0.14), value: isFocused)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

struct CleanMenuPicker: View {
    let title: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button {
                    selection = opt
                } label: {
                    if selection == opt {
                        Label(opt, systemImage: "checkmark")
                    } else {
                        Text(opt)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.textMuted)
            }
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.softCardBg))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct CleanPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(disabled ? AppTheme.textSecondary.opacity(0.75) : Color.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(disabled ? AppTheme.neutralPill : AppTheme.brandPrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(disabled ? AppTheme.subtleBorder : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct CleanSmallButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering: Bool = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5.5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovering ? AppTheme.neutralPill : AppTheme.softCardBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isHovering ? AppTheme.inputBorder : AppTheme.subtleBorder, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct CleanChipButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    init(_ title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AppTheme.brandPrimary : AppTheme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? AppTheme.brandSoftFill : AppTheme.softCardBg))
                .overlay(Capsule().strokeBorder(selected ? Color.clear : AppTheme.subtleBorder, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
