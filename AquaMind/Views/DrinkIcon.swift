import SwiftUI

extension DrinkKind {
    var tint: Color {
        switch self {
        case .water: return Color(red: 0.28, green: 0.87, blue: 0.98)
        case .tea: return Color(red: 0.83, green: 0.59, blue: 0.31)
        case .coffee: return Color(red: 0.61, green: 0.36, blue: 0.23)
        case .juice: return Color(red: 1.00, green: 0.66, blue: 0.21)
        case .soda: return Color(red: 0.70, green: 0.53, blue: 1.00)
        case .milk: return Color(red: 0.81, green: 0.91, blue: 1.00)
        case .compote: return Color(red: 0.98, green: 0.38, blue: 0.52)
        case .broth: return Color(red: 0.97, green: 0.76, blue: 0.39)
        case .other: return Color(red: 0.47, green: 0.82, blue: 0.67)
        }
    }

    var shadowTint: Color {
        switch self {
        case .coffee: return Color(red: 0.28, green: 0.15, blue: 0.10)
        case .tea: return Color(red: 0.42, green: 0.26, blue: 0.13)
        case .soda: return Color(red: 0.28, green: 0.20, blue: 0.52)
        case .juice: return Color(red: 0.53, green: 0.25, blue: 0.10)
        default: return tint.opacity(0.45)
        }
    }

    /// Rendered artwork from the five approved AquaMind drink designs.
    /// Water, tea, coffee and "Other" keep their original native vector icons.
    var artworkName: String? {
        switch self {
        case .juice: return "DrinkJuice"
        case .soda: return "DrinkSoda"
        case .milk: return "DrinkMilk"
        case .compote: return "DrinkCompote"
        case .broth: return "DrinkBroth"
        default: return nil
        }
    }

    var symbol: String {
        switch self {
        case .water: return "drop.fill"
        case .tea: return "cup.and.saucer.fill"
        case .coffee: return "mug.fill"
        case .juice: return "wineglass.fill"
        case .soda: return "takeoutbag.and.cup.and.straw.fill"
        case .milk: return "water.waves"
        case .compote: return "wineglass.fill"
        case .broth: return "fork.knife"
        case .other: return "sparkles"
        }
    }
}

/// Layered native SwiftUI artwork with per-drink palette, shine and accents.
/// Drawn at runtime, so it stays sharp on both iPhone and iPad/Watch notification previews.
struct DrinkIcon: View {
    let kind: DrinkKind
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let assetName = kind.artworkName {
                Image(assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.29,
                                                style: .continuous))
            } else {
                vectorArtwork
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(kind.title)
    }

    private var vectorArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(LinearGradient(
                    colors: [kind.tint.opacity(0.33), kind.shadowTint.opacity(0.42)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .strokeBorder(kind.tint.opacity(0.33), lineWidth: 1)
            Circle()
                .fill(kind.tint.opacity(0.18))
                .frame(width: size * 0.60)
                .blur(radius: size * 0.13)
                .offset(x: size * 0.12, y: size * 0.10)
            Image(systemName: kind.symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.white, kind.tint],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing))
                .shadow(color: kind.tint.opacity(0.45), radius: size * 0.07)
            if kind == .soda {
                Circle().fill(.white.opacity(0.85))
                    .frame(width: size * 0.055, height: size * 0.055)
                    .offset(x: -size * 0.25, y: -size * 0.21)
                Circle().fill(.white.opacity(0.65))
                    .frame(width: size * 0.085, height: size * 0.085)
                    .offset(x: size * 0.27, y: size * 0.18)
            } else if kind == .tea {
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.16))
                    .foregroundStyle(Color(red: 0.76, green: 0.97, blue: 0.65))
                    .offset(x: size * 0.21, y: -size * 0.18)
            } else if kind == .juice || kind == .compote {
                Circle().strokeBorder(.white.opacity(0.8), lineWidth: size * 0.025)
                    .frame(width: size * 0.15, height: size * 0.15)
                    .offset(x: size * 0.24, y: -size * 0.20)
            } else if kind == .coffee {
                Image(systemName: "flame.fill")
                    .font(.system(size: size * 0.15))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(x: size * 0.24, y: -size * 0.22)
            }
            RoundedRectangle(cornerRadius: size * 0.12)
                .fill(.white.opacity(0.16))
                .frame(width: size * 0.38, height: size * 0.065)
                .rotationEffect(.degrees(-28))
                .offset(x: -size * 0.15, y: -size * 0.30)
        }
        .frame(width: size, height: size)
    }
}


/// Native neon tile used by personal profiles and preserved history snapshots.
enum PersonalDrinkPalette {
    static let choices: [Color] = [
        Color(red: 0.28, green: 0.87, blue: 0.98),
        Color(red: 0.85, green: 0.60, blue: 0.34),
        Color(red: 0.95, green: 0.40, blue: 0.58),
        Color(red: 0.66, green: 0.54, blue: 1.0),
        Color(red: 0.38, green: 0.85, blue: 0.63),
        Color(red: 0.99, green: 0.70, blue: 0.27),
        Color(red: 0.40, green: 0.65, blue: 1.0),
        Color(red: 0.90, green: 0.48, blue: 0.90),
        Color(red: 0.49, green: 0.29, blue: 0.18),
        Color(red: 0.36, green: 0.22, blue: 0.15),
        Color(red: 0.66, green: 0.42, blue: 0.26),
        Color(red: 0.57, green: 0.36, blue: 0.30),
        Color(red: 0.78, green: 0.56, blue: 0.37),
        Color(red: 0.85, green: 0.69, blue: 0.52),
        Color(red: 0.99, green: 0.43, blue: 0.26),
        Color(red: 0.78, green: 0.24, blue: 0.28),
        Color(red: 0.58, green: 0.24, blue: 0.47),
        Color(red: 0.20, green: 0.57, blue: 0.47),
        Color(red: 0.25, green: 0.69, blue: 0.43),
        Color(red: 0.52, green: 0.77, blue: 0.26),
        Color(red: 0.97, green: 0.82, blue: 0.40),
        Color(red: 0.98, green: 0.55, blue: 0.15),
        Color(red: 0.13, green: 0.43, blue: 0.72),
        Color(red: 0.28, green: 0.30, blue: 0.71),
        Color(red: 0.49, green: 0.32, blue: 0.74),
        Color(red: 0.94, green: 0.61, blue: 0.75),
        Color(red: 0.95, green: 0.83, blue: 0.69),
        Color(red: 0.53, green: 0.73, blue: 0.79)
    ]
    static let names: [String] = [
        "Бирюзовый", "Медовый", "Розовый", "Сиреневый",
        "Мятный", "Золотой", "Голубой", "Лиловый",
        "Какао",
        "Шоколад",
        "Карамель",
        "Мокко",
        "Латте",
        "Кремовый",
        "Коралловый",
        "Вишнёвый",
        "Смородина",
        "Изумрудный",
        "Яблочный",
        "Лаймовый",
        "Лимонный",
        "Манго",
        "Сапфировый",
        "Индиго",
        "Черничный",
        "Клубничный",
        "Молочная пена",
        "Ледяной",
    ]
    static func name(_ index: Int) -> String {
        names[min(names.count - 1, max(0, index))]
    }
    static func tint(_ index: Int) -> Color {
        choices[min(choices.count-1, max(0, index))]
    }
}

struct PersonalDrinkIcon: View {
    let name: String
    let symbol: String
    let palette: Int
    var size: CGFloat = 52

    private var tint: Color { PersonalDrinkPalette.tint(palette) }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26)
                .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.08)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.26)
                .strokeBorder(tint.opacity(0.7), lineWidth: 1)
            Circle().fill(tint.opacity(0.26)).blur(radius: size * 0.14)
            if symbol == DrinkIconCatalog.bubbleTeaSymbol {
                BubbleTeaGlyph(size: size * 0.72)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: tint, radius: size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(name)
    }
}

struct EntryDrinkIcon: View {
    let entry: WaterEntry
    var size: CGFloat = 36
    var profiles: [CustomDrink] = []

    var body: some View {
        let identity = AnalyticsDrinkIdentity(entry: entry, profiles: profiles)
        Group {
            if let name = identity.customName {
                PersonalDrinkIcon(name: name,
                                  symbol: identity.customSymbol ?? "drop.fill",
                                  palette: identity.customPalette ?? 0,
                                  size: size)
            } else {
                DrinkIcon(kind: entry.kind, size: size)
            }
        }
    }
}

extension WaterEntry {
    var displayTint: Color {
        if let index = customDrinkPalette { return PersonalDrinkPalette.tint(index) }
        return kind.tint
    }
}


extension AnalyticsDrinkIdentity {
    var tint: Color {
        if let palette = customPalette { return PersonalDrinkPalette.tint(palette) }
        return kind.tint
    }
}

extension AnalyticsDrink {
    var tint: Color { identity.tint }
}

extension AnalyticsBucket {
    var tint: Color { identity.tint }
}

struct AnalyticsDrinkIcon: View {
    let drink: AnalyticsDrink
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let name = drink.identity.customName {
                PersonalDrinkIcon(
                    name: name,
                    symbol: drink.identity.customSymbol ?? "drop.fill",
                    palette: drink.identity.customPalette ?? 0,
                    size: size)
            } else {
                DrinkIcon(kind: drink.kind, size: size)
            }
        }
    }
}


/// Original bubble tea glyph: takeaway cup, straw, tapioca pearls.
struct BubbleTeaGlyph: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Capsule().fill(.white).frame(width: size * 0.09, height: size * 0.67)
                .rotationEffect(.degrees(13))
                .offset(x: size * 0.15, y: -size * 0.14)
            Path { p in
                p.move(to: CGPoint(x: size * 0.12, y: size * 0.28))
                p.addLine(to: CGPoint(x: size * 0.88, y: size * 0.28))
                p.addLine(to: CGPoint(x: size * 0.76, y: size * 0.94))
                p.addQuadCurve(to: CGPoint(x: size * 0.24, y: size * 0.94),
                               control: CGPoint(x: size * 0.5, y: size * 1.0))
                p.closeSubpath()
            }.fill(.white.opacity(0.87))
            Ellipse().fill(.white)
                .frame(width: size * 0.82, height: size * 0.17)
                .offset(y: -size * 0.23)
            ForEach(0..<5, id: \.self) { index in
                let positions: [(CGFloat, CGFloat)] = [
                    (-0.21, 0.25), (0.01, 0.27), (0.22, 0.24),
                    (-0.12, 0.11), (0.14, 0.10)
                ]
                Circle().fill(Color(red: 0.29, green: 0.17, blue: 0.12))
                    .frame(width: size * 0.13, height: size * 0.13)
                    .offset(x: size * positions[index].0,
                            y: size * positions[index].1)
            }
        }.frame(width: size, height: size)
         .accessibilityLabel("Бабл-ти со стаканом, трубочкой и шариками")
    }
}
