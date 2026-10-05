import SwiftUI

struct TemplateFillRequest: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var template: String
    var fields: [TemplateField]
    var values: [String: String]
    var plain: Bool
}

struct TemplateFillView: View {
    var request: TemplateFillRequest
    var theme: Theme
    var onPaste: (String) -> Void
    var onCancel: () -> Void
    @State private var values: [String: String]

    init(
        request: TemplateFillRequest,
        theme: Theme,
        onPaste: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.theme = theme
        self.onPaste = onPaste
        self.onCancel = onCancel
        _values = State(initialValue: request.values)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fill in")
                        .font(.system(size: 14, weight: .semibold))
                    Text(request.title)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(14)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(request.fields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.secondary)
                            TextField(field.label, text: binding(for: field.key))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(theme.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.secondary)
                        Text(SnippetTemplate.render(request.template, values: values))
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(theme.separator)
                            )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Paste") {
                    onPaste(SnippetTemplate.render(request.template, values: values))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .frame(width: 420, height: min(520, CGFloat(220 + request.fields.count * 64)))
        .background(theme.background)
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }
}
