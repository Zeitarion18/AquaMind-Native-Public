import SwiftUI
import UIKit

/// All preferences are stored locally in hydration.json. Existing history is
/// not rewritten when profiles or vessels are edited or deleted.
struct PersonalizationView: View {
    @EnvironmentObject private var store: HydrationStore
    @State private var editingDrink: CustomDrink?
    @State private var editingVessel: DrinkVessel?
    @State private var favoriteAmount = 250

    var body: some View {
        Form {
            quickButtonsSection
            customDrinksSection
            vesselsSection
            favoriteSection
        }
        .scrollContentBackground(.hidden)
        .background(AquaTheme.background)
        .navigationTitle("Персонализация")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingDrink) { drink in
            CustomDrinkEditor(drink: drink)
        }
        .sheet(item: $editingVessel) { vessel in
            VesselEditor(vessel: vessel)
        }
    }

    private var quickButtonsSection: some View {
        Section {
            ForEach(0..<3, id: \.self) { index in
                Stepper(
                    "Кнопка \(index + 1): \(store.settings.quickVolumes[index]) мл",
                    value: Binding(
                        get: { store.settings.quickVolumes[index] },
                        set: { store.setQuickVolume(at: index, milliliters: $0) }),
                    in: 25...1000, step: 25
                )
                .font(.subheadline)
            }
        } header: {
            Text("Быстрые объёмы")
        } footer: {
            Text("Эти три значения отображаются на главном экране. Настраиваются с шагом 25 мл.")
        }
    }

    private var customDrinksSection: some View {
        Section {
            ForEach(store.settings.customDrinks) { drink in
                Button { editingDrink = drink } label: {
                    HStack(spacing: 12) {
                        PersonalDrinkIcon(name: drink.name,
                                          symbol: drink.symbol,
                                          palette: drink.palette, size: 42)
                        Text(drink.name).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(AquaTheme.muted)
                    }
                }
            }
            .onDelete { indexSet in
                let current = store.settings.customDrinks
                for index in indexSet where current.indices.contains(index) {
                    store.deleteCustomDrink(current[index].id)
                }
            }

            Button {
                editingDrink = CustomDrink(name: "", symbol: "drop.fill", palette: 0)
            } label: {
                Label("Создать свой напиток", systemImage: "plus.circle.fill")
                    .foregroundStyle(AquaTheme.cyan)
            }
        } header: {
            Text("Мои напитки")
        } footer: {
            Text("Любой напиток получит собственные название, иконку и цвет. При удалении профиля старые записи в истории сохранятся.")
        }
    }

    private var vesselsSection: some View {
        Section {
            ForEach(store.settings.vessels) { vessel in
                Button { editingVessel = vessel } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "cup.and.saucer.fill")
                            .foregroundStyle(AquaTheme.cyan)
                            .frame(width: 42, height: 40)
                        Text(vessel.name).foregroundStyle(.white)
                        Spacer()
                        Text("\(vessel.milliliters) мл")
                            .foregroundStyle(AquaTheme.muted)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(AquaTheme.muted)
                    }
                }
            }
            .onDelete { indexSet in
                let current = store.settings.vessels
                for index in indexSet where current.indices.contains(index) {
                    store.deleteVessel(current[index].id)
                }
            }
            Button {
                editingVessel = DrinkVessel(name: "", milliliters: 250)
            } label: {
                Label("Добавить стакан или бутылку", systemImage: "plus.circle.fill")
                    .foregroundStyle(AquaTheme.cyan)
            }
        } header: {
            Text("Моя посуда")
        } footer: {
            Text("На главном экране можно одним касанием записать полный объём выбранной посуды. Напиток берётся из текущего выбора.")
        }
    }

    private var favoriteSection: some View {
        Section {
            Stepper("Объём избранного: \(favoriteAmount) мл",
                    value: $favoriteAmount, in: 25...1000, step: 25)

            Button {
                store.saveFavoriteForSelection(favoriteAmount)
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                Label("Добавить: \(store.selectedDrinkTitle)",
                      systemImage: "heart.circle.fill")
                    .foregroundStyle(AquaTheme.cyan)
            }
            .disabled(store.settings.favorites.count >= 8)

            ForEach(store.settings.favorites) { favorite in
                HStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                    Text(favoriteName(favorite))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text("+\(favorite.milliliters) мл")
                        .foregroundStyle(AquaTheme.cyan)
                }
            }
            .onDelete { indexSet in
                let current = store.settings.favorites
                for index in indexSet where current.indices.contains(index) {
                    store.deleteFavorite(current[index].id)
                }
            }
        } header: {
            Text("Избранные сочетания")
        } footer: {
            Text("Сначала выбери напиток на главном экране, затем сохрани его с любимым объёмом здесь. До 8 сочетаний; на главном экране они появляются отдельными кнопками.")
        }
    }

    private func favoriteName(_ favorite: DrinkFavorite) -> String {
        if let id = favorite.customDrinkID,
           let profile = store.settings.customDrinks.first(where: { $0.id == id }) {
            return profile.name
        }
        return favorite.customName ?? favorite.kind.title
    }
}

private struct CustomDrinkEditor: View {
    @EnvironmentObject private var store: HydrationStore
    @Environment(\.dismiss) private var dismiss
    @State private var drink: CustomDrink
    @State private var showingCatalog = false
    @FocusState private var nameFieldFocused: Bool

    init(drink: CustomDrink) {
        _drink = State(initialValue: drink)
    }

    private var canSave: Bool {
        !drink.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 13) {
                        PersonalDrinkIcon(
                            name: drink.name.isEmpty ? "Напиток" : drink.name,
                            symbol: drink.symbol, palette: drink.palette, size: 92)
                        Text(drink.name.isEmpty ? "Твой напиток" : drink.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Предпросмотр карточки")
                            .font(.caption)
                            .foregroundStyle(AquaTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { nameFieldFocused = false }
                    .listRowBackground(Color.clear)

                    TextField("Например, бабл-ти", text: $drink.name)
                        .focused($nameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { nameFieldFocused = false }
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                        .onChange(of: drink.name) { _, newValue in
                            drink.name = String(newValue.prefix(32))
                        }
                } header: {
                    Text("Название и предпросмотр")
                }

                Section("Иконка") {
                    Button {
                        // Dismiss the name keyboard before presenting the icon sheet.
                        // The @State draft survives loss of focus.
                        nameFieldFocused = false
                        showingCatalog = true
                    } label: {
                        HStack(spacing: 12) {
                            PersonalDrinkIcon(
                                name: drink.name,
                                symbol: drink.symbol, palette: drink.palette, size: 45)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(DrinkIconCatalog.option(drink.symbol)?.title ?? "Иконка")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("Открыть каталог из \(DrinkIconCatalog.all.count) иконок")
                                    .font(.caption)
                                    .foregroundStyle(AquaTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(AquaTheme.cyan)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Text("Выбранный цвет: \(PersonalDrinkPalette.name(drink.palette))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 5),
                        spacing: 13
                    ) {
                        ForEach(PersonalDrinkPalette.choices.indices, id: \.self) { index in
                            Button {
                                nameFieldFocused = false
                                drink.palette = index
                            } label: {
                                Circle()
                                    .fill(PersonalDrinkPalette.tint(index).gradient)
                                    .frame(width: 39, height: 39)
                                    .overlay {
                                        if drink.palette == index {
                                            Image(systemName: "checkmark")
                                                .font(.headline.bold())
                                                .foregroundStyle(.white)
                                                .shadow(color: .black.opacity(0.8), radius: 2)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(PersonalDrinkPalette.name(index))
                            .accessibilityAddTraits(drink.palette == index ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, 7)
                } header: {
                    Text("Цвет и оттенок")
                } footer: {
                    Text("Коричневые оттенки: какао, шоколад, карамель, мокко и латте. Старые цвета сохраняются.")
                }

                Button("Сохранить напиток") {
                    nameFieldFocused = false
                    store.saveCustomDrink(drink)
                    dismiss()
                }
                .disabled(!canSave)
                .font(.headline)
                .foregroundStyle(AquaTheme.cyan)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AquaTheme.background)
            .navigationTitle("Мой напиток")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Отмена") {
                        nameFieldFocused = false
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { nameFieldFocused = false }
                        .fontWeight(.semibold)
                        .tint(AquaTheme.cyan)
                }
            }
            .sheet(isPresented: $showingCatalog) {
                DrinkIconPicker(selectedSymbol: $drink.symbol, palette: drink.palette)
            }
        }
    }
}

private struct VesselEditor: View {
    @EnvironmentObject private var store: HydrationStore
    @Environment(\.dismiss) private var dismiss
    @State private var vessel: DrinkVessel
    @FocusState private var vesselNameFocused: Bool

    init(vessel: DrinkVessel) {
        _vessel = State(initialValue: vessel)
    }

    private var canSave: Bool {
        !vessel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Например, моя кружка", text: $vessel.name)
                        .focused($vesselNameFocused)
                        .submitLabel(.done)
                        .onSubmit { vesselNameFocused = false }
                        .textInputAutocapitalization(.sentences)
                        .onChange(of: vessel.name) { _, newValue in
                            vessel.name = String(newValue.prefix(32))
                        }
                    Stepper("Объём: \(vessel.milliliters) мл",
                            value: $vessel.milliliters, in: 25...2000, step: 25)
                    Text("Один клик по этой посуде запишет указанный объём текущего напитка.")
                        .font(.footnote).foregroundStyle(AquaTheme.muted)
                }
                Button("Сохранить посуду") {
                    vesselNameFocused = false
                    store.saveVessel(vessel)
                    dismiss()
                }
                .disabled(!canSave)
                .font(.headline)
                .foregroundStyle(AquaTheme.cyan)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AquaTheme.background)
            .navigationTitle("Моя посуда")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Отмена") {
                        vesselNameFocused = false
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { vesselNameFocused = false }
                        .fontWeight(.semibold)
                        .tint(AquaTheme.cyan)
                }
            }
        }
    }
}
