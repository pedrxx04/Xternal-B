import SwiftUI

/// Full-screen gate shown before anything else in the app (even before
/// onboarding): nothing else renders until `KeyGateStore.state == .unlocked`.
struct KeyGateView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var store: KeyGateStore
    @State private var input = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 12)

                AppLogo(size: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(radius: 8)

                VStack(spacing: 6) {
                    Text(language.text("key.gate.title"))
                        .font(.title2.weight(.semibold))
                    Text(language.text("key.gate.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                switch store.state {
                case .checking:
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(language.text("key.gate.checking"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                case .needsKey(let errorKey):
                    formSection(errorKey: errorKey)

                case .unlocked:
                    EmptyView()
                }

                Spacer()
            }
            .padding(.horizontal, AppTheme.pageInset)
        }
    }

    private func formSection(errorKey: String?) -> some View {
        VStack(spacing: 14) {
            TextField(language.text("key.gate.placeholder"), text: $input)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .multilineTextAlignment(.center)
                .focused($fieldFocused)
                .submitLabel(.go)
                .onSubmit(attemptSubmit)
                .padding(.horizontal, 11)
                .frame(minHeight: 44)
                .background(
                    Color(uiColor: .secondarySystemFill),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            if let errorKey {
                Text(language.text(errorKey))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: attemptSubmit) {
                Text(language.text("key.gate.unlock"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 8)
        .onAppear { fieldFocused = true }
    }

    private func attemptSubmit() {
        let value = input
        fieldFocused = false
        Task { await store.submit(key: value) }
    }
}
