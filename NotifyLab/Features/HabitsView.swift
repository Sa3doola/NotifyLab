import SwiftUI

struct HabitsView: View {
    @Environment(HabitScheduler.self) private var scheduler
    @Environment(NotificationPermission.self) private var permission
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                if permission.status == .notDetermined {
                    Section {
                        // Ask in context: right when reminders become useful, not at first launch.
                        Button {
                            Task { await permission.requestFull() }
                        } label: {
                            Label("Turn on reminders", systemImage: "bell.badge")
                        }
                    } footer: {
                        Text("We ask here, next to the habits, because this is the moment the prompt makes sense.")
                    }
                }

                Section("Today") {
                    ForEach(scheduler.habits) { habit in
                        HabitRow(habit: habit)
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { scheduler.habits[$0] }
                        Task { for habit in doomed { await scheduler.delete(habit) } }
                    }
                }

                Section {
                    ForEach(Habit.Level.allCases, id: \.self) { level in
                        Button {
                            Task { await scheduler.fireTest(level: level) }
                        } label: {
                            Label("\(level.title): arrives in 5 s", systemImage: icon(for: level))
                        }
                    }
                } header: {
                    Text("Compare interruption levels")
                } footer: {
                    Text("Tap one, then lock the device (⌘L in the Simulator). Passive won't light up the screen. Long-press any reminder to see Done, Snooze and Add a note.")
                }

                Section {
                    ForEach(scheduler.pending.prefix(12)) { reminder in
                        LabeledContent(reminder.title) {
                            Text(reminder.date?.formatted(.dateTime.weekday(.abbreviated).hour().minute()) ?? "—")
                        }
                    }
                } header: {
                    Text("Scheduled: \(scheduler.pending.count) of \(HabitScheduler.systemLimit)")
                } footer: {
                    Text(scheduler.droppedCount > 0
                         ? "\(scheduler.droppedCount) later reminders didn't fit. They'll be scheduled when the app next runs."
                         : "iOS keeps at most 64 pending notifications per app. We schedule the next 14 days and top up every time the app runs.")
                }
            }
            .navigationTitle("Habits")
            .toolbar {
                Button { isAdding = true } label: { Label("Add habit", systemImage: "plus") }
            }
            .sheet(isPresented: $isAdding) { AddHabitView() }
            .task { await scheduler.refreshPending() }
        }
    }

    private func icon(for level: Habit.Level) -> String {
        switch level {
        case .passive: "moon"
        case .active: "bell"
        case .timeSensitive: "exclamationmark.circle"
        }
    }
}

private struct HabitRow: View {
    @Environment(HabitScheduler.self) private var scheduler
    let habit: Habit

    var body: some View {
        let done = scheduler.isDoneToday(habit)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name).font(.headline)
                Text("\(habit.timeText) · \(habit.daysText) · \(habit.level.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let streak = scheduler.streak(for: habit)
                if streak > 0 {
                    Text("\(streak)-day streak").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                }
            }
            Spacer()
            Button {
                Task { await scheduler.markDone(habit.id) }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(done)
            .accessibilityLabel(done ? "Done today" : "Mark done")
        }
    }
}

private struct AddHabitView: View {
    @Environment(HabitScheduler.self) private var scheduler
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var weekdays: Set<Int> = Set(1...7)
    @State private var level: Habit.Level = .active

    var body: some View {
        NavigationStack {
            Form {
                TextField("Habit name", text: $name)
                DatePicker("Remind me at", selection: $time, displayedComponents: .hourAndMinute)
                Section("Days") {
                    let symbols = Calendar.current.weekdaySymbols
                    ForEach(1...7, id: \.self) { day in
                        Toggle(symbols[day - 1], isOn: Binding(
                            get: { weekdays.contains(day) },
                            set: { isOn in if isOn { weekdays.insert(day) } else { weekdays.remove(day) } }))
                    }
                }
                Picker("Interruption level", selection: $level) {
                    ForEach(Habit.Level.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            .navigationTitle("New habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                        let habit = Habit(name: name, hour: parts.hour ?? 9, minute: parts.minute ?? 0,
                                          weekdays: weekdays, level: level)
                        Task { await scheduler.add(habit) }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || weekdays.isEmpty)
                }
            }
        }
    }
}
