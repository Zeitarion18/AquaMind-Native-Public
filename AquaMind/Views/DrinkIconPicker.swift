import SwiftUI
import UIKit

/// Searchable offline catalogue. System glyphs are checked on the actual iOS
/// version, so unsupported SF Symbols never produce invisible picker buttons.
struct DrinkIconPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedSymbol: String
    let palette: Int

    @State private var search = ""
    @State private var category = "Все"
    @FocusState private var searchFieldFocused: Bool

    private var options: [DrinkIconOption] {
        DrinkIconCatalog.find(search, category: category == "Все" ? nil : category)
            .filter {
                $0.symbol == DrinkIconCatalog.bubbleTeaSymbol ||
                UIImage(systemName: $0.symbol) != nil
            }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AquaTheme.cyan)
                    TextField("Например, бабл, кофе, сок…", text: $search)
                        .focused($searchFieldFocused)
                        .submitLabel(.search)
                        .onSubmit { searchFieldFocused = false }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.white)
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AquaTheme.muted)
                        }
                        .accessibilityLabel("Очистить поиск")
                    }
                }
                .padding(13)
                .background(AquaTheme.panel,
                            in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["Все"] + DrinkIconCatalog.categories, id: \.self) { item in
                            Button {
                                searchFieldFocused = false
                                category = item
                            } label: {
                                Text(item)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(category == item ? .black : .white)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 9)
                                    .background(category == item ? AquaTheme.cyan : AquaTheme.panel,
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                HStack {
                    Text("Найдено иконок: \(options.count)")
                        .font(.caption)
                        .foregroundStyle(AquaTheme.muted)
                    Spacer()
                    Text("\(DrinkIconCatalog.all.count) в каталоге")
                        .font(.caption)
                        .foregroundStyle(AquaTheme.cyan)
                }
                .padding(.horizontal, 18)

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 76, maximum: 118),
                                           spacing: 10)],
                        spacing: 11
                    ) {
                        ForEach(options) { option in
                            let chosen = selectedSymbol == option.symbol
                            Button {
                                searchFieldFocused = false
                                selectedSymbol = option.symbol
                                UISelectionFeedbackGenerator().selectionChanged()
                                dismiss()
                            } label: {
                                VStack(spacing: 7) {
                                    PersonalDrinkIcon(
                                        name: option.title,
                                        symbol: option.symbol,
                                        palette: palette,
                                        size: 48)
                                    Text(option.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(chosen ? .white : AquaTheme.muted)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.75)
                                        .multilineTextAlignment(.center)
                                        .frame(height: 27)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(chosen ? AquaTheme.cyan.opacity(0.14)
                                                : AquaTheme.panel,
                                            in: RoundedRectangle(cornerRadius: 15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15)
                                        .strokeBorder(chosen ? AquaTheme.cyan : .clear,
                                                      lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.title)
                            .accessibilityAddTraits(chosen ? [.isSelected] : [])
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    if options.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.top, 15)
            .background(AquaTheme.background.ignoresSafeArea())
            .navigationTitle("Иконки напитков")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") {
                        searchFieldFocused = false
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { searchFieldFocused = false }
                        .fontWeight(.semibold)
                        .tint(AquaTheme.cyan)
                }
            }
        }
    }
}
