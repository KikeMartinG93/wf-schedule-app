import SwiftUI

/// CS Sup–only tab. Safe codes / liquor case content lands later; this is the shell.
struct KeysView: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ContentUnavailableView {
                    Label("Keys", systemImage: "key.fill")
                } description: {
                    Text("Safe codes, liquor case, and other store keys will show up here.")
                } actions: {
                    Text("Coming soon")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.current.readableAccent)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaBar(edge: .top) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Keys")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color(uiColor: .label))
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }
}
