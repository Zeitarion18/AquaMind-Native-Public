import SwiftUI

/// Seven independent daily schedules; times are stored as wall-clock minutes
/// in the AquaMind-selected time zone, not as absolute Date values.
struct WeeklyScheduleView: View {
    @EnvironmentObject private var store: HydrationStore

    var body: some View {
        Form {
            Section {
                ForEach(DaySchedule.orderedWeekdays, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(store.settings.schedule(for: day).label)
                                .font(.headline).foregroundStyle(.white)
                            Spacer()
                            if day == 1 || day == 7 {
                                Text("Выходной")
                                    .font(.caption2).foregroundStyle(AquaTheme.muted)
                            } else {
                                Text("Будни")
                                    .font(.caption2).foregroundStyle(AquaTheme.muted)
                            }
                        }
                        HStack {
                            Label("Начало дня", systemImage: "sunrise")
                                .font(.subheadline)
                            Spacer()
                            Picker("Начало дня", selection: Binding(
                                get: { store.settings.schedule(for: day).wakeMinute },
                                set: { store.setDaySchedule(weekday: day, wakeMinute: $0) }
                            )) {
                                ForEach(0..<288, id: \.self) { index in
                                    let minute = index * 5
                                    Text(DaySchedule.timeLabel(minute)).tag(minute)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .tint(AquaTheme.cyan)
                        }
                        HStack {
                            Label("Конец дня", systemImage: "moon.stars")
                                .font(.subheadline)
                            Spacer()
                            Picker("Конец дня", selection: Binding(
                                get: { store.settings.schedule(for: day).sleepMinute },
                                set: { store.setDaySchedule(weekday: day, sleepMinute: $0) }
                            )) {
                                ForEach(0..<288, id: \.self) { index in
                                    let minute = index * 5
                                    Text(DaySchedule.timeLabel(minute)).tag(minute)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .tint(AquaTheme.cyan)
                        }
                        if store.settings.schedule(for: day).sleepMinute <=
                           store.settings.schedule(for: day).wakeMinute {
                            Text("Завершение дня — после полуночи.")
                                .font(.caption2).foregroundStyle(AquaTheme.muted)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Расписание недели")
            } footer: {
                Text("Будни по умолчанию: 06:30. Выходные: 11:30. Любой день можно изменить независимо. Напоминания пересчитываются автоматически.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AquaTheme.background)
        .navigationTitle("Режим дня")
        .navigationBarTitleDisplayMode(.inline)
    }
}
