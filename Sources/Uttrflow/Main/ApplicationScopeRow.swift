// The editor line that confines a snippet or a word to applications the person chooses.

import SwiftUI
import UttrflowCore
import UttrflowUX

/// "Only in" with the chosen applications and buttons to add one or go back to every app.
struct ApplicationScopeRow: View {
    let line: ApplicationScopeLine
    @Binding var applications: [String]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "app.badge")
                .font(.system(size: 11))
                .foregroundStyle(PagePalette.faint)
                .accessibilityHidden(true)
            Text(line.label)
                .font(.system(size: 12))
                .foregroundStyle(PagePalette.text.opacity(0.6))
            Text(line.summary)
                .font(.system(size: 12))
                .foregroundStyle(PagePalette.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button(line.choose) {
                ApplicationPicker.chooseScopeApplication { chosen in
                    applications = ApplicationScope.normalised(applications + [chosen])
                }
            }
            .buttonStyle(PageButtonStyle())
            if let clear = line.clear {
                Button(clear) { applications = [] }
                    .buttonStyle(PageButtonStyle())
            }
        }
        .accessibilityElement(children: .contain)
    }
}
