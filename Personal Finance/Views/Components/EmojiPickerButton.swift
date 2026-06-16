import SwiftUI

// MARK: - Emoji Picker Button

struct EmojiPickerButton: View {
    @Binding var emoji: String
    var size: CGFloat = 44
    var background: Color = Color(.systemGray5)

    @State private var showPicker = false

    var body: some View {
        Button { showPicker = true } label: {
            Text(emoji.isEmpty ? "📦" : emoji)
                .font(.system(size: size * 0.55))
                .frame(width: size, height: size)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            EmojiPickerSheet(selected: $emoji, isPresented: $showPicker)
        }
    }
}

// MARK: - Picker Sheet

private struct EmojiPickerSheet: View {
    @Binding var selected: String
    @Binding var isPresented: Bool
    @State private var search = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var sections: [EmojiSection] {
        if search.isEmpty { return emojiData }
        let filtered = emojiData.compactMap { section -> EmojiSection? in
            let hits = section.emojis.filter { $0.contains(search) }
            return hits.isEmpty ? nil : EmojiSection(title: section.title, emojis: hits)
        }
        return filtered
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20, pinnedViews: .sectionHeaders) {
                    ForEach(sections) { section in
                        Section {
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(section.emojis, id: \.self) { emoji in
                                    Button {
                                        selected = emoji
                                        isPresented = false
                                    } label: {
                                        Text(emoji)
                                            .font(.system(size: 28))
                                            .frame(maxWidth: .infinity)
                                            .aspectRatio(1, contentMode: .fit)
                                            .background(
                                                selected == emoji
                                                    ? Color.blue.opacity(0.15)
                                                    : Color.clear
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } header: {
                            Text(section.title)
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                                .background(Color(.systemGroupedBackground))
                        }
                    }
                }
                .padding(.horizontal)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search emoji")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - Data

private struct EmojiSection: Identifiable {
    let id = UUID()
    let title: String
    let emojis: [String]
}

private let emojiData: [EmojiSection] = [
    EmojiSection(title: "💰 Money", emojis: [
        "💰","💵","💴","💶","💷","💸","💳","🏦","🏧","💹","📈","📉","🤑","💎","🪙","🏷️","🧾","📊"
    ]),
    EmojiSection(title: "🛒 Shopping", emojis: [
        "🛒","🛍️","🏪","🏬","🏭","👜","👛","💍","🎁","🪆","🧸","📦"
    ]),
    EmojiSection(title: "🍔 Food & Drink", emojis: [
        "🍔","🍕","🍜","🍣","🥗","🥘","🥩","🍗","🌮","🥪","☕","🍺","🍷","🥤","🧃","🎂","🍰","🧋"
    ]),
    EmojiSection(title: "🚗 Transport", emojis: [
        "🚗","🚕","🚙","🚌","🛵","🏍️","🚲","🛺","✈️","🚂","⛽","🚢","🚁","🛻","🚐","🚎"
    ]),
    EmojiSection(title: "🏥 Health", emojis: [
        "💊","🏥","🩺","🧬","🏃","🏋️","🧘","🦷","👓","🩹","🩻","💉","🩸","🧪"
    ]),
    EmojiSection(title: "🏠 Home", emojis: [
        "🏠","🏡","🏢","🏗️","💡","🔧","🛋️","🧹","🪴","🛁","🚿","🧺","🔑","🚪","🪑"
    ]),
    EmojiSection(title: "📱 Tech", emojis: [
        "📱","💻","🖥️","⌨️","🖨️","📷","📸","🎧","📡","🔋","💾","🖱️","⌚","📺"
    ]),
    EmojiSection(title: "🎮 Entertainment", emojis: [
        "🎮","🎬","🎵","🎸","🎭","📚","🎲","🎯","⚽","🏀","🎾","🏊","🎨","🎪","🎡"
    ]),
    EmojiSection(title: "🎓 Education", emojis: [
        "📚","🎓","✏️","📝","📐","🔬","🏫","📖","📓","📒","✒️"
    ]),
    EmojiSection(title: "👕 Clothing", emojis: [
        "👕","👗","👟","👠","🧥","👒","🕶️","👔","👖","🧣","🧤","💄"
    ]),
    EmojiSection(title: "✈️ Travel", emojis: [
        "🌍","🏖️","🏔️","🎡","🏨","🗺️","📸","🧳","🗼","🏝️","🌋","⛰️","🎢"
    ]),
    EmojiSection(title: "⭐ Other", emojis: [
        "⭐","❤️","✅","🎯","🔔","📌","🗓️","📋","💼","🌟","🌈","🎀","🏆","🥇","🎖️","🚀","🌙","☀️","🔥","💫"
    ]),
]
