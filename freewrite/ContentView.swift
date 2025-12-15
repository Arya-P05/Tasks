import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("colorScheme") private var colorSchemeSetting: String = "system"
    @StateObject private var store = TaskStore()

    @State private var draftTitle: String = ""
    @State private var editingTaskId: UUID? = nil
    @State private var editingTitle: String = ""

    @State private var showUndo: Bool = false
    @State private var hoveredBucket: TaskBucket? = nil
    @State private var isFullscreenHovered: Bool = false
    @State private var isThemeHovered: Bool = false
    @State private var isHistoryHovered: Bool = false
    @State private var showingHistory: Bool = false
    @State private var isFullscreen: Bool = false
    @FocusState private var isInputFocused: Bool

    private let selectedFontName = "Lato-Regular"
    private let fontSize: CGFloat = 16
    
    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()

            if showingHistory {
                HistoryView(
                    fontName: selectedFontName,
                    fontSize: fontSize,
                    completed: store.completedTasksSorted(),
                    onClose: { showingHistory = false }
                )
                .frame(maxWidth: 650)
                .padding(.vertical, 24)
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    header
                    input
                    list
                }
                .frame(maxWidth: 650)
                .padding(.vertical, 24)
                .transition(.opacity)

                if showUndo && store.canUndoComplete() {
                    undoToast
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            bottomRightBar
        }
        .onChange(of: store.shouldShowCarryoverPrompt) {
            // Keep toast out of the way when the prompt is up.
            if store.shouldShowCarryoverPrompt {
                withAnimation { showUndo = false }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshDailyPrompt()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            isFullscreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
            isFullscreen = false
        }
        .alert("New day.", isPresented: $store.shouldShowCarryoverPrompt) {
            Button("Carry over unfinished") {
                store.applyCarryoverDecision(.carryOver)
            }
            Button("Clear Today") {
                store.applyCarryoverDecision(.clearTodayToThisWeek)
            }
            Button("Cancel", role: .cancel) {
                store.applyCarryoverDecision(.cancel)
            }
        } message: {
            Text("Carry over unfinished Today tasks?")
        }
        .animation(.easeInOut(duration: 0.15), value: showingHistory)
    }

    // MARK: - Palette

    private var appBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        // Keep secondary copy consistent across themes
        Color.gray.opacity(colorScheme == .dark ? 0.78 : 0.72)
    }

    private var surface: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
    }

    private var surfaceBorder: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.10)
    }

    private var accentBlue: Color {
        // Tiny, minimal accent. Slightly softer than system blue.
        Color(red: 0.36, green: 0.62, blue: 1.00)
    }

    private var header: some View {
        HStack(spacing: 12) {
            bucketTabs
                        
                        Spacer()
                        
            // intentionally minimal “status”: show count
            let count = store.tasks(in: store.selectedBucket).count
            Text("\(count)")
                .font(.custom(selectedFontName, size: 13))
                .foregroundStyle(secondaryText)
                .accessibilityLabel("\(count) tasks")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var bucketTabs: some View {
        HStack(spacing: 6) {
            ForEach(TaskBucket.allCases) { bucket in
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        store.selectedBucket = bucket
                    }
                } label: {
                    Text(bucket.title)
                        .font(.custom(selectedFontName, size: 13))
                        .foregroundStyle(bucketTextColor(bucket))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                .background(
                    Capsule()
                        .fill(bucketBackgroundColor(bucket))
                )
                    .overlay(
                    Capsule()
                        .stroke(bucketBorderColor(bucket), lineWidth: 1)
                )
                            .onHover { hovering in
                    hoveredBucket = hovering ? bucket : nil
                }
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color(.textBackgroundColor).opacity(0.10))
        )
    }

    private func bucketBorderColor(_ bucket: TaskBucket) -> Color {
        // Intentionally subtle, to keep the “no UI chrome” vibe.
        surfaceBorder.opacity(colorScheme == .dark ? 0.8 : 0.7)
    }

    private func bucketBackgroundColor(_ bucket: TaskBucket) -> Color {
        let isSelected = store.selectedBucket == bucket
        let isHovered = hoveredBucket == bucket

        if isSelected {
            return colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.06)
        }
        if isHovered {
            return colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.03)
        }
        return .clear
    }

    private func bucketTextColor(_ bucket: TaskBucket) -> Color {
        store.selectedBucket == bucket ? primaryText : secondaryText
    }

    private var bottomRightBar: some View {
                VStack {
                    Spacer()
                    HStack {
                Spacer()
                        HStack(spacing: 8) {
                    Button(isFullscreen ? "Minimize" : "Fullscreen") { toggleFullscreen() }
                            .buttonStyle(.plain)
                        .font(.custom(selectedFontName, size: 13))
                        .foregroundStyle(isFullscreenHovered ? primaryText : secondaryText)
                            .onHover { hovering in
                            isFullscreenHovered = hovering
                            }
                            
                            Text("•")
                        .foregroundStyle(secondaryText)

                    Button(action: cycleTheme) {
                        Image(systemName: themeIconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isThemeHovered ? primaryText : secondaryText)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                            isThemeHovered = hovering
                        }
                        .help(themeHelpText)
                        .accessibilityLabel(themeHelpText)
                            
                            Text("•")
                        .foregroundStyle(secondaryText)

                    Button(action: { showingHistory.toggle() }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isHistoryHovered ? primaryText : secondaryText)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                            isHistoryHovered = hovering
                        }
                        .help(showingHistory ? "Back" : "History")
                        .accessibilityLabel(showingHistory ? "Back" : "History")
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
        .allowsHitTesting(true)
    }

    private var themeIconName: String {
        switch colorSchemeSetting {
        case "light":
            return "sun.max.fill"
        case "dark":
            return "moon.fill"
        default:
            return "laptopcomputer"
        }
    }

    private var themeHelpText: String {
        switch colorSchemeSetting {
        case "light":
            return "Theme: Light"
        case "dark":
            return "Theme: Dark"
        default:
            return "Theme: System"
        }
    }

    private func cycleTheme() {
        // System -> Light -> Dark -> System
        switch colorSchemeSetting {
        case "system":
            colorSchemeSetting = "light"
        case "light":
            colorSchemeSetting = "dark"
        default:
            colorSchemeSetting = "system"
        }
    }

    private func toggleFullscreen() {
        if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first {
            window.toggleFullScreen(nil)
        }
    }

    private var input: some View {
        HStack(spacing: 10) {
            TextField("Add a task…", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.custom(selectedFontName, size: fontSize))
                .foregroundStyle(primaryText)
                .focused($isInputFocused)
                // This affects caret + selection tint; use a tiny blue accent.
                .tint(accentBlue)
                .onSubmit(addDraftTask)

            // Keep the UI single-action: the “button” is optional, subtle.
            Button(action: addDraftTask) {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryText)
                                        }
                                        .buttonStyle(.plain)
            .help("Add (Enter)")
            .opacity(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.2 : 1.0)
            .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
                                            .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(surfaceBorder, lineWidth: 1)
        )
                                            .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.tasks(in: store.selectedBucket)) { task in
                    taskRow(task)
                    Divider().opacity(0.5)
                }
            }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private func taskRow(_ task: TodoTask) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    store.completeTask(id: task.id)
                    showUndo = true
                }

                // Auto-hide undo
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            withAnimation(.easeOut(duration: 0.2)) {
                        showUndo = false
                    }
                }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
            .help("Complete")

            if editingTaskId == task.id {
                TextField("", text: $editingTitle)
                    .textFieldStyle(.plain)
                    .font(.custom(selectedFontName, size: fontSize))
                    .onSubmit {
                        store.updateTaskTitle(id: task.id, title: editingTitle)
                        editingTaskId = nil
                        editingTitle = ""
                    }
                                } else {
                Button {
                    editingTaskId = task.id
                    editingTitle = task.title
                } label: {
                    Text(task.title)
                        .font(.custom(selectedFontName, size: fontSize))
                        .foregroundStyle(primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                .help("Edit")
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var undoToast: some View {
        VStack {
                                                Spacer()
            HStack(spacing: 10) {
                Text("Completed")
                    .font(.custom(selectedFontName, size: 13))
                    .foregroundStyle(.secondary)

                Button("Undo") {
                    withAnimation(.easeOut(duration: 0.12)) {
                        store.undoLastComplete()
                        showUndo = false
                    }
                                                        }
                                                        .buttonStyle(.plain)
                .font(.custom(selectedFontName, size: 13))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
                                    .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.textBackgroundColor).opacity(0.25))
            )
            .padding(.bottom, 16)
        }
        .frame(maxWidth: 650)
    }

    private func addDraftTask() {
        store.addTask(title: draftTitle, bucket: store.selectedBucket)
        draftTitle = ""
    }
}

private struct HistoryView: View {
    let fontName: String
    let fontSize: CGFloat
    let completed: [TodoTask]
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isBackHovered: Bool = false

    private let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df
    }()

    private let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df
    }()

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        Color.gray.opacity(colorScheme == .dark ? 0.78 : 0.72)
    }

    private var accentBlue: Color {
        Color(red: 0.36, green: 0.62, blue: 1.00)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { onClose() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isBackHovered ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help("Back")
                .onHover { hovering in
                    isBackHovered = hovering
                }

                Spacer()

                Text("History")
                    .font(.custom(fontName, size: 13))
                    .foregroundStyle(secondaryText)

                Spacer()

                Text("\(completed.count)")
                    .font(.custom(fontName, size: 13))
                    .foregroundStyle(secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedDays, id: \.dayKey) { group in
                        Text(group.dayKey)
                            .font(.custom(fontName, size: 13))
                            .foregroundStyle(secondaryText)
                            .padding(.top, 14)
                            .padding(.bottom, 6)

                        ForEach(group.tasks) { task in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(accentBlue.opacity(colorScheme == .dark ? 0.90 : 0.85))
                                    // visually center the icon against the title line (not the full title+time block)
                                    .padding(.top, max(CGFloat(0), (fontSize - 15) / 2) + 4)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.custom(fontName, size: fontSize))
                                        .foregroundStyle(primaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(timeString(task.completedAt))
                                        .font(.custom(fontName, size: 11))
                                        .foregroundStyle(secondaryText)
                                }
                            }
                            .padding(.vertical, 10)

                            if task.id != group.tasks.last?.id {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
    }

    private func timeString(_ date: Date?) -> String {
        guard let date else { return "" }
        return timeFormatter.string(from: date)
    }

    private var groupedDays: [(dayKey: String, tasks: [TodoTask])] {
        let groups = Dictionary(grouping: completed) { task in
            dayFormatter.string(from: task.completedAt ?? .distantPast)
        }

        // Sort days by newest completion
        let sortedKeys = groups.keys.sorted { a, b in
            // We don’t have the date objects for keys easily, so derive by looking up first task time.
            let aMax = groups[a]?.compactMap(\.completedAt).max() ?? .distantPast
            let bMax = groups[b]?.compactMap(\.completedAt).max() ?? .distantPast
            return aMax > bMax
        }

        return sortedKeys.map { key in
            let tasks = (groups[key] ?? []).sorted {
                ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
            }
            return (dayKey: key, tasks: tasks)
        }
    }
}

#Preview {
    ContentView()
}
