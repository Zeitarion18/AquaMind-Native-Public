import SwiftUI
import UIKit

/// Approximate volume presets. The stored entry is explicitly marked with ≈.
struct EstimateDrinkSheet: View {
    @EnvironmentObject private var store: HydrationStore
    @Environment(\.dismiss) private var dismiss
    private let options: [(String, Int, String)] = [
        ("Несколько глотков", 50, "drop"),
        ("Немного", 100, "drop.halffull"),
        ("Половина стакана", 125, "glass.filled"),
        ("Обычный стакан", 250, "cup.and.saucer.fill")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Оцени объём приблизительно. Можно записать напиток, даже когда не знаешь точное количество миллилитров.")
                        .font(.subheadline).foregroundStyle(AquaTheme.muted)
                    ForEach(options, id: \.1) { option in
                        Button {
                            store.addSelected(option.1, estimated: true)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.2)
                                    .foregroundStyle(AquaTheme.cyan)
                                    .frame(width: 28)
                                Text(option.0).foregroundStyle(.white)
                                Spacer()
                                Text("≈ \(option.1) мл")
                                    .foregroundStyle(AquaTheme.cyan)
                                    .font(.subheadline.bold())
                            }
                            .padding(15)
                            .background(AquaTheme.panel,
                                        in: RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("AquaMind учитывает приблизительный объём в дневной сумме, но отмечает его символом ≈ в истории.")
                        .font(.footnote).foregroundStyle(AquaTheme.muted)
                }
                .padding(18)
            }
            .background(AquaTheme.background.ignoresSafeArea())
            .navigationTitle("Сколько выпил?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
