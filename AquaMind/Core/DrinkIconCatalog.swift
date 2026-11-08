import Foundation

struct DrinkIconOption: Hashable, Identifiable {
    let symbol: String
    let title: String
    let category: String
    let keywords: String
    var id: String { symbol }

    func matches(_ search: String) -> Bool {
        let text = "\(title) \(category) \(keywords) \(symbol)"
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let parts = search.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                   locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
        return parts.allSatisfy { text.contains(String($0)) }
    }
}

/// Curated symbols, plus an original vector boba cup. The catalogue contains
/// 176 distinct icons and is entirely offline on iPhone.
enum DrinkIconCatalog {
    static let bubbleTeaSymbol = "aquamind.boba"

    static let all: [DrinkIconOption] = {
        let categories: [(String, [(String, String, String)])] = [
        ("Вода и освежающие", [
            ("drop.fill", "Капля воды", "вода чистая"),
            ("drop", "Контур капли", "капля"),
            ("drop.circle.fill", "Вода в круге", "вода"),
            ("drop.circle", "Капля в контуре", "вода"),
            ("drop.triangle.fill", "Капля в треугольнике", "вода"),
            ("drop.triangle", "Треугольная капля", "вода"),
            ("water.waves", "Волны", "вода море"),
            ("humidity.fill", "Влажность", "вода"),
            ("humidity", "Увлажнение", "вода"),
            ("faucet.fill", "Кран", "вода"),
            ("faucet", "Кран контур", "вода"),
            ("shower.fill", "Душ", "прохлада"),
            ("shower", "Душ контур", "прохлада"),
            ("cloud.rain.fill", "Дождь", "дождевой"),
            ("cloud.drizzle.fill", "Морось", "освежает"),
            ("water.waves.and.arrow.down", "Поток воды", "вода")
        ]),
        ("Чай и травы", [
            ("cup.and.saucer.fill", "Чашка чая", "чай горячий"),
            ("cup.and.saucer", "Чашка", "чай"),
            ("leaf.fill", "Чайный лист", "чай травы"),
            ("leaf", "Лист", "зеленый чай"),
            ("leaf.circle.fill", "Травяной чай", "травы"),
            ("leaf.circle", "Травяной настой", "чай"),
            ("tree.fill", "Лесной чай", "травы"),
            ("tree", "Дерево", "травы"),
            ("flame.fill", "Крепкий горячий чай", "нагрев"),
            ("flame", "Горячий напиток", "тепло"),
            ("sun.haze.fill", "Тёплый настой", "тепло"),
            ("cloud.fog.fill", "Ароматный чай", "пар"),
            ("wind", "Аромат", "чай"),
            ("wind.circle.fill", "Ароматный пар", "чай"),
            ("thermometer.medium", "Средняя температура", "температура"),
            ("thermometer.high", "Горячее", "чай")
        ]),
        ("Кофе и какао", [
            ("mug.fill", "Кружка кофе", "кофе какао"),
            ("mug", "Кружка контур", "кофе"),
            ("sun.max.fill", "Утренний кофе", "утро кофе"),
            ("sun.max", "Утро", "кофе"),
            ("sunrise.fill", "Раннее утро", "кофе"),
            ("sunrise", "Рассвет", "утро"),
            ("moon.stars.fill", "Ночной кофе", "ночь"),
            ("moon.stars", "Ночь", "ночь"),
            ("bolt.fill", "Эспрессо", "кофе бодрость"),
            ("bolt", "Бодрость", "кофе"),
            ("bolt.circle.fill", "Крепкий кофе", "кофе"),
            ("flame.circle.fill", "Горячий шоколад", "какао"),
            ("flame.circle", "Тепло", "какао"),
            ("heart.fill", "Какао с любовью", "какао"),
            ("heart", "Сердце", "какао"),
            ("heart.circle.fill", "Любимый напиток", "кофе")
        ]),
        ("Молоко и десерты", [
            ("waterbottle.fill", "Бутылка молока", "молоко бутылка"),
            ("waterbottle", "Бутылка", "молоко"),
            ("snowflake", "Холодное молоко", "холод"),
            ("snowflake.circle.fill", "Ледяное молоко", "холод"),
            ("snowflake.circle", "Снежная капля", "холод"),
            ("cloud.fill", "Молочная пенка", "молоко пена"),
            ("cloud", "Облачко", "молоко"),
            ("birthday.cake.fill", "Десертный напиток", "десерт"),
            ("birthday.cake", "Сладкий десерт", "десерт"),
            ("gift.fill", "Сладкий подарок", "десерт"),
            ("gift", "Угощение", "десерт"),
            ("moon.fill", "Молоко перед сном", "молоко"),
            ("moon", "Молочный вечер", "молоко"),
            ("circle.hexagongrid.fill", "Молочные пузырьки", "пена"),
            ("circle.grid.3x3.fill", "Пенистый напиток", "пузырьки"),
            ("cloud.moon.fill", "Нежный напиток", "молоко")
        ]),
        ("Соки и фрукты", [
            ("carrot.fill", "Морковный сок", "морковь сок"),
            ("carrot", "Морковь", "овощной"),
            ("camera.macro", "Фруктовый цветок", "фрукты сок"),
            ("camera.macro.circle.fill", "Ягодный цветок", "ягода"),
            ("sun.min.fill", "Цитрусовый сок", "лимон апельсин"),
            ("sun.min", "Цитрус", "лимон"),
            ("sun.max.circle.fill", "Солнечный сок", "апельсин"),
            ("sun.max.circle", "Лимонад", "лимон"),
            ("rainbow", "Фруктовый микс", "разноцветный"),
            ("globe.europe.africa.fill", "Тропический сок", "тропики"),
            ("globe.americas.fill", "Экзотические фрукты", "фрукты"),
            ("globe.asia.australia.fill", "Азийский напиток", "фрукты"),
            ("circle.dotted", "Ягодный сок", "ягоды"),
            ("circle.hexagongrid", "Ягодный микс", "ягоды"),
            ("fork.knife", "Фреш", "фрукты"),
            ("fork.knife.circle.fill", "Натуральный сок", "фрукты")
        ]),
        ("Газировка и лимонад", [
            ("bubbles.and.sparkles.fill", "Пузырьки", "газировка"),
            ("sparkles", "Шипучий напиток", "газировка"),
            ("sparkle", "Искра", "газировка"),
            ("star.fill", "Звёздная газировка", "газировка"),
            ("star", "Звезда", "газировка"),
            ("star.circle.fill", "Блестящий напиток", "газировка"),
            ("star.circle", "Маленькие пузырьки", "газировка"),
            ("atom", "Искристый напиток", "газировка"),
            ("aqi.high", "Газированный", "пузырьки"),
            ("tornado", "Бурлящий", "газировка"),
            ("hurricane", "Коктейль-шторм", "газировка"),
            ("bolt.heart.fill", "Энергия", "энергетик"),
            ("bolt.circle", "Молния в кружке", "энергетик"),
            ("wand.and.stars", "Волшебный лимонад", "газировка"),
            ("wand.and.stars.inverse", "Волшебные пузырьки", "газировка"),
            ("asterisk", "Искристый сироп", "газировка")
        ]),
        ("Бабл-ти и коктейли", [
            ("aquamind.boba", "Бабл-ти с тапиокой", "бабл боба boba bubble tea шарики трубочка тапиока"),
            ("takeoutbag.and.cup.and.straw.fill", "Стакан с трубочкой", "бабл лимонад"),
            ("takeoutbag.and.cup.and.straw", "Трубочка", "коктейль"),
            ("wineglass.fill", "Коктейль", "коктейли"),
            ("wineglass", "Бокал", "коктейль"),
            ("party.popper.fill", "Праздничный коктейль", "вечеринка"),
            ("party.popper", "Праздничный напиток", "праздник"),
            ("balloon.fill", "Воздушный напиток", "бабл"),
            ("balloon", "Шарики", "бабл"),
            ("circle.grid.cross.fill", "Шарики тапиоки", "боба"),
            ("circle.grid.cross", "Тапиока", "бабл"),
            ("smallcircle.filled.circle.fill", "Жемчужинки", "тапиока"),
            ("circle.circle.fill", "Желейные шарики", "бабл"),
            ("circle.circle", "Кружочки", "бабл"),
            ("heart.circle", "Милый коктейль", "милкшейк"),
            ("heart.square.fill", "Любимый коктейль", "коктейль")
        ]),
        ("Смузи и полезные", [
            ("leaf.arrow.circlepath", "Зелёный смузи", "смузи детокс"),
            ("fork.knife.circle", "Смузи", "смузи"),
            ("figure.mind.and.body", "Здоровый напиток", "смузи"),
            ("face.smiling.fill", "Вкусняшка", "смузи"),
            ("face.smiling", "Улыбка", "смузи"),
            ("brain.head.profile", "Полезный напиток", "витамины"),
            ("brain", "Для концентрации", "смузи"),
            ("cross.vial.fill", "Витаминный микс", "витамины"),
            ("cross.vial", "Эликсир", "витамины"),
            ("heart.text.square.fill", "Полезный коктейль", "здоровье"),
            ("heart.text.square", "Здоровье", "напиток"),
            ("waveform.path.ecg", "Восстановление", "полезный"),
            ("waveform.path.ecg.rectangle.fill", "Ритм", "полезный"),
            ("cross.circle.fill", "Тоник", "полезный"),
            ("cross.circle", "Травяной тоник", "полезный"),
            ("person.crop.circle.fill", "Личный рецепт", "смузи")
        ]),
        ("Спорт и энергетики", [
            ("dumbbell.fill", "Спортивный шейк", "спорт протеин"),
            ("dumbbell", "Шейкер для спорта", "спорт"),
            ("figure.run", "Бег", "изотоник"),
            ("figure.walk", "Ходьба", "вода"),
            ("figure.hiking", "Походный напиток", "поход"),
            ("figure.swimming", "Плавание", "спорт"),
            ("bicycle", "Велосипед", "спорт"),
            ("figure.cycling", "Велотренировка", "спорт"),
            ("figure.strengthtraining.traditional", "Силовая тренировка", "протеин"),
            ("figure.strengthtraining.functional", "Тренировка", "спорт"),
            ("figure.rower", "Гребля", "спорт"),
            ("figure.cooldown", "Восстановление", "спорт"),
            ("figure.yoga", "Йога", "спорт"),
            ("bolt.batteryblock.fill", "Энергетический напиток", "энергетик"),
            ("battery.100percent", "Энергия 100%", "энергетик"),
            ("figure.outdoor.cycle", "Прогулка", "спорт")
        ]),
        ("Посуда и упаковка", [
            ("basket.fill", "Корзинка", "бутылка"),
            ("basket", "Корзина", "напиток"),
            ("backpack.fill", "Рюкзак с водой", "поход"),
            ("backpack", "Рюкзак", "поход"),
            ("bag.fill", "Пакет напитка", "упаковка"),
            ("bag", "Пакет", "упаковка"),
            ("shippingbox.fill", "Упаковка", "коробка"),
            ("shippingbox", "Коробка", "пакет"),
            ("archivebox.fill", "Контейнер", "упаковка"),
            ("archivebox", "Короб", "бутылка"),
            ("tray.fill", "Поднос", "подача"),
            ("tray", "Поднос контур", "подача"),
            ("cube.fill", "Кубик льда", "лёд"),
            ("cube", "Лёд", "лёд"),
            ("cylinder.split.1x2.fill", "Банка напитка", "банка"),
            ("cylinder.split.1x2", "Баночка", "банка")
        ]),
        ("Атмосфера и оформление", [
            ("diamond.fill", "Премиум напиток", "дизайн"),
            ("diamond", "Кристалл", "напиток"),
            ("hexagon.fill", "Медовый напиток", "мёд"),
            ("hexagon", "Соты", "мёд"),
            ("octagon.fill", "Фирменный напиток", "дизайн"),
            ("octagon", "Восьмиугольник", "дизайн"),
            ("suit.heart.fill", "Романтичный", "любимый"),
            ("suit.club.fill", "Клевер", "удача"),
            ("suit.diamond.fill", "Бриллиант", "красивый"),
            ("suit.spade.fill", "Пика", "тёмный"),
            ("circle.hexagongrid.circle.fill", "Ячейки", "фруктовый"),
            ("star.square.fill", "Звезда в квадрате", "красивый"),
            ("star.square", "Звезда", "дизайн"),
            ("moon.circle.fill", "Ночной напиток", "сон"),
            ("sunset.fill", "Вечерний напиток", "закат"),
            ("mountain.2.fill", "Горный источник", "вода")
        ])
        ]
        return categories.flatMap { category, options in
            options.map { symbol, title, keywords in
                DrinkIconOption(symbol: symbol, title: title,
                                category: category, keywords: keywords)
            }
        }
    }()

    static var categories: [String] {
        var found: [String] = []
        for option in all where !found.contains(option.category) {
            found.append(option.category)
        }
        return found
    }

    static func isSupported(_ symbol: String) -> Bool {
        all.contains { $0.symbol == symbol }
    }

    static func find(_ query: String, category: String? = nil) -> [DrinkIconOption] {
        all.filter {
            (category == nil || $0.category == category) &&
            (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
             $0.matches(query))
        }
    }

    static func option(_ symbol: String) -> DrinkIconOption? {
        all.first { $0.symbol == symbol }
    }
}
