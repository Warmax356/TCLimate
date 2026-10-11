import SwiftUI
import AppKit
import Combine
import TCLCore

struct AirPanel: View {
    @ObservedObject var store: AppStore
    @StateObject private var launchAtLogin = LaunchAtLogin()
    @State private var contentHeight: CGFloat?
    private let poll = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            // An explicit height lets MenuBarExtra size its window; scrolls past the cap.
            ScrollView {
                content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: contentHeight.map { min($0, 540) })
        }
        .frame(width: 340)
        .tint(.gray)
        .background(WindowTopAnchor())
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
        .onReceive(poll) { _ in
            if NSApplication.shared.keyWindow?.isVisible == true { Task { await store.refresh() } }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            status
            if store.connected { devices } else { SignInForm(store: store) }
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text("TCLimate").font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if store.connected {
                Button { Task { await store.refresh() } } label: {
                    if store.busy { ProgressView().controlSize(.small).frame(width: 16, height: 16) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(HeaderButtonStyle())
                .disabled(store.busy || !store.pendingDevices.isEmpty)
                .help("Refresh")
                .keyboardShortcut("r")
            }
            Menu {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin.isRequested },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.requiresApproval {
                    Button("Approve in Login Items…") { launchAtLogin.openSettings() }
                }
                Divider()
                if store.connected {
                    Section(store.email) {
                        Button("Sign Out") { store.signOut() }
                            .disabled(store.busy || !store.pendingDevices.isEmpty)
                    }
                }
                Button("Quit TCLimate") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(HeaderButtonStyle())
            .fixedSize()
            .help("More")
        }
        .padding(.leading, 16).padding(.trailing, 10).padding(.top, 12).padding(.bottom, 2)
    }

    private var subtitle: String {
        guard store.connected else { return store.busy ? "Connecting…" : "Not signed in" }
        let count = store.devices.count
        let units = count == 1 ? "1 air conditioner" : "\(count) air conditioners"
        guard let date = store.lastUpdated else { return units }
        return "\(units) · Updated \(date.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder private var status: some View {
        if let error = launchAtLogin.error {
            Banner(text: error, symbol: "exclamationmark.triangle.fill", tint: .red)
        } else if launchAtLogin.requiresApproval {
            VStack(alignment: .leading, spacing: 6) {
                Text("Launch at login needs approval in System Settings.").font(.caption)
                Button("Open Login Items…") { launchAtLogin.openSettings() }
                    .font(.caption)
            }
        }
        if let error = store.error {
            Banner(text: error, symbol: "exclamationmark.triangle.fill", tint: .red)
        } else if let notice = store.notice {
            Banner(text: notice, symbol: store.pendingDevices.isEmpty ? "checkmark.circle.fill" : "clock", tint: .secondary)
        }
    }

    @ViewBuilder private var devices: some View {
        if store.devices.isEmpty {
            VStack(spacing: 6) {
                ACGlyph(active: false, width: 36)
                Text("No air conditioners").font(.headline)
                Text("Pair your ACs with this account in the TCL Home app, then refresh.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.vertical, 24)
        }
        ForEach(store.devices) { device in
            DeviceCard(energyStore: store, device: device, pending: store.pendingDevices.contains(device.id), busy: store.busy) { command in
                Task { await store.send(command, to: device) }
            }
        }
    }
}

/// Bare icon button; a soft highlight appears only on hover or press.
private struct HeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverIcon(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct HoverIcon<Label: View>: View {
        let label: Label
        let pressed: Bool
        @State private var hovering = false

        var body: some View {
            label
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.primary.opacity(pressed ? 0.12 : hovering ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// Monochrome primary action: inverted label on a solid primary fill.
private struct MonoProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.background)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(.primary.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.3)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct Banner: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label { Text(text).foregroundStyle(.primary) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
            .font(.caption)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SignInForm: View {
    @ObservedObject var store: AppStore
    @State private var revealPassword = false
    private var canSubmit: Bool {
        !store.busy && !store.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.password.isEmpty
    }

    var body: some View {
        if let step = store.connectStep {
            ConnectingView(step: step, email: store.email) { store.cancelConnect() }
        } else {
            form
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                ACGlyph(active: true, width: 48)
                Text("Sign in to TCL Home").font(.title3.weight(.semibold))
                Text("Use the account your air conditioners are paired with.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.top, 4)

            VStack(spacing: 0) {
                row("envelope") {
                    TextField("Email", text: $store.email).textContentType(.username)
                }
                Divider().padding(.leading, 36)
                row("lock") {
                    Group {
                        if revealPassword { TextField("TCL password", text: $store.password) }
                        else { SecureField("TCL password", text: $store.password) }
                    }
                    .textContentType(.password)
                    .onSubmit { if canSubmit { Task { await store.signIn() } } }
                    Button { revealPassword.toggle() } label: {
                        Image(systemName: revealPassword ? "eye.slash" : "eye").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).help(revealPassword ? "Hide Password" : "Show Password")
                }
                Divider().padding(.leading, 36)
                row("globe") {
                    Text("Region").foregroundStyle(.secondary)
                    Spacer()
                    Picker("Region", selection: $store.region) {
                        Text("Pakistan / Singapore").tag(AccountRegion.singapore)
                        Text("Europe").tag(AccountRegion.europe)
                        Text("United States").tag(AccountRegion.usa)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
            }
            .textFieldStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.1)))

            Toggle(isOn: $store.remember) {
                Label("Remember in Keychain", systemImage: "key")
            }
            .toggleStyle(.checkbox).font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { Task { await store.signIn() } } label: {
                Label("Sign In", systemImage: "arrow.right.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(MonoProminentButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)

            Label {
                Text("Signed in with Google? Set a TCL password in TCL Home › Account Security and use it here. Never enter your Google password.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func row<Content: View>(_ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
            content()
        }
        .padding(.horizontal, 10).frame(height: 36)
    }
}

private struct ConnectingView: View {
    let step: ConnectStep
    let email: String
    let cancel: () -> Void
    @State private var spinning = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().stroke(.primary.opacity(0.1), lineWidth: 3)
                Circle().trim(from: 0, to: 0.28)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                Image(nsImage: MenuBarIcon.snowflake(size: 28, lineWidth: 1.6)).renderingMode(.template)
                    .foregroundStyle(.primary)
            }
            .frame(width: 64, height: 64)
            .onAppear { withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spinning = true } }
            .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text("Connecting to TCL Home").font(.title3.weight(.semibold))
                if !email.isEmpty { Text(email).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }

            VStack(alignment: .leading, spacing: 10) {
                stepRow(.signingIn, "Signing in to your account", symbol: "person.badge.key")
                stepRow(.findingDevices, "Finding your air conditioners", symbol: nil)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))

            Button("Cancel", action: cancel).controlSize(.large).keyboardShortcut(.cancelAction)
        }
        .padding(.vertical, 8)
        .animation(.snappy, value: step)
    }

    private func stepRow(_ row: ConnectStep, _ title: String, symbol: String?) -> some View {
        HStack(spacing: 10) {
            Group {
                if row.rawValue < step.rawValue {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.primary)
                } else if row == step {
                    ProgressView().controlSize(.small)
                } else if let symbol {
                    Image(systemName: symbol).foregroundStyle(.tertiary)
                } else {
                    ACGlyph(active: false, width: 14)
                }
            }
            .frame(width: 18, height: 18)
            Text(title).font(.callout).foregroundStyle(row.rawValue <= step.rawValue ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DeviceCard: View {
    @ObservedObject var energyStore: AppStore
    @State private var showEnergy = false
    @State private var showControls = false
    let device: AirConditioner
    let pending: Bool
    let busy: Bool
    let send: (ACCommand) -> Void
    private var enabled: Bool { device.isOnline && device.isSupported && !pending && !busy }
    private var active: Bool { device.isOnline && device.statusMessage == nil && device.power }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ACGlyph(active: active)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                powerButton
            }
            if device.isSupported, let target = device.targetTemperature {
                HStack(alignment: .center) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(target, specifier: "%.0f")")
                            .font(.system(size: 34, weight: .light)).monospacedDigit()
                            .contentTransition(.numericText(value: target))
                        Text("°C").font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Target \(target, specifier: "%.0f") degrees")
                    Spacer()
                    HStack(spacing: 8) {
                        stepButton("minus", label: "Lower temperature", value: target - 1)
                        stepButton("plus", label: "Raise temperature", value: target + 1)
                    }
                }
                .opacity(device.power ? 1 : 0.4)
            } else if let message = unsupportedMessage {
                Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if (device.isSupported && device.hasExtraControls) || (device.isSupported && device.isOnline) {
                VStack(alignment: .leading, spacing: 0) {
                    if device.isSupported && device.hasExtraControls {
                        sectionHeader("Controls", summary: showControls ? nil : controlsSummary, expanded: showControls) {
                            showControls.toggle()
                        }
                        if showControls { extraControls.padding(.bottom, 10).transition(.opacity) }
                    }
                    if device.isSupported && device.isOnline {
                        if device.hasExtraControls { Divider() }
                        sectionHeader("Electricity", summary: showEnergy ? nil : energySummary, expanded: showEnergy) {
                            showEnergy.toggle()
                            if showEnergy, energyStore.energyReports[device.id] == nil {
                                Task { await energyStore.loadEnergy(for: device) }
                            }
                        }
                        if showEnergy { energyContent.padding(.bottom, 4).transition(.opacity) }
                    }
                }
                .padding(.top, -4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .animation(.snappy, value: device.targetTemperature)
    }

    private func sectionHeader(_ title: String, summary: String?, expanded: Bool, toggle: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { toggle() } } label: {
            HStack(spacing: 6) {
                Text(title).font(.callout)
                Spacer()
                if let summary { Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(expanded ? "Hide" : "Show") \(title.lowercased())")
    }

    private var energySummary: String? {
        guard let today = energyStore.energyReports[device.id]?.todayKWh else { return nil }
        return "Today \(today.formatted(.number.precision(.fractionLength(2)))) kWh"
    }

    private var energyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let report = energyStore.energyReports[device.id] {
                if let message = report.message {
                    Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 12) {
                        energyTile("Today", value: report.todayKWh, emphasized: true)
                        energyTile("Yesterday", value: report.yesterdayKWh)
                        energyTile("7 days", value: report.weekKWh)
                    }
                    EnergyChart(report: report)
                }
            }
            if let error = energyStore.energyErrors[device.id] {
                Text(error).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .center, spacing: 6) {
                if energyStore.pendingEnergy.contains(device.id) {
                    ProgressView().controlSize(.mini)
                    Text("Updating…")
                } else if let report = energyStore.energyReports[device.id] {
                    Text("Updated \(report.fetchedAt.formatted(date: .omitted, time: .shortened))")
                }
                Spacer()
                Button { Task { await energyStore.loadEnergy(for: device) } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                        .frame(height: 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(energyStore.pendingEnergy.contains(device.id))
                .help("Refresh electricity")
                .accessibilityLabel("Refresh electricity for \(device.name)")
            }
            .foregroundStyle(.tertiary)
        }.font(.caption)
    }

    private func energyTile(_ title: String, value: Double?, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map { $0.formatted(.number.precision(.fractionLength($0 < 100 ? 2 : 1))) } ?? "—")
                    .font(.system(size: 15, weight: emphasized ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(value == nil ? .tertiary : .primary)
                if value != nil { Text("kWh").foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value.map { "\($0.formatted(.number.precision(.fractionLength(2)))) kilowatt hours" } ?? "no reading")")
    }

    private var statusText: String {
        guard device.isOnline else { return "Offline" }
        guard device.statusMessage == nil else { return "State unavailable" }
        let power = device.power ? "On" : "Off"
        guard let room = device.currentTemperature else { return power }
        return "\(power) · \(room.formatted(.number.precision(.fractionLength(0))))°C indoors"
    }

    private var controlsEnabled: Bool { enabled && device.power }

    private var controlsSummary: String? {
        let parts = [device.mode?.title, device.fanSpeed.map { "Fan \($0.title)" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var extraControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !device.power {
                Label("Turn on the AC to change these settings.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Group {
                if !device.modes.isEmpty { modeTiles }
                settingsGroup {
                    if !device.fanSpeeds.isEmpty {
                        settingRow("Fan", "fan") {
                            optionMenu(device.fanSpeed?.title ?? "Custom",
                                       selection: Binding<ACFanSpeed?>(get: { device.fanSpeed }, set: { if let value = $0 { send(.fan(value)) } })) {
                                ForEach(device.fanSpeeds) { Text($0.title).tag(Optional($0)) }
                            }
                        }
                        .disabled(device.mode == .dry)
                    }
                    ForEach(ACAxis.allCases) { axis in
                        if device.supportsAirflow(axis) {
                            settingRow(axis.title, axis == .vertical ? "arrow.up.and.down" : "arrow.left.and.right") {
                                optionMenu(device.airflow(axis)?.title(for: axis) ?? "Custom",
                                           selection: Binding<ACAirflow?>(get: { device.airflow(axis) }, set: { if let value = $0 { send(.airflow(axis, value)) } })) {
                                    ForEach(ACAirflow.allCases) { Text($0.title(for: axis)).tag(Optional($0)) }
                                }
                            }
                        }
                    }
                    if let sleep = device.sleep {
                        settingRow("Sleep", "moon.zzz") {
                            optionMenu(sleep.title,
                                       selection: Binding<ACSleep?>(get: { device.sleep }, set: { if let value = $0 { send(.sleep(value)) } })) {
                                ForEach(ACSleep.allCases) { Text($0.title).tag(Optional($0)) }
                            }
                        }
                        .disabled(device.mode != .cool && device.mode != .heat && sleep == .off)
                    }
                }
                settingsGroup {
                    ForEach(ACFeature.allCases) { option in
                        if let value = device.feature(option) {
                            settingRow(option.title, option.symbol) {
                                Toggle(option.title, isOn: Binding(get: { value }, set: { send(.feature(option, $0)) }))
                                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                            }
                            .disabled(option == .eco && !value && device.mode != .cool)
                        }
                    }
                }
            }
            .disabled(!controlsEnabled)
            .opacity(controlsEnabled ? 1 : 0.45)
        }
    }

    private var modeTiles: some View {
        HStack(spacing: 6) {
            ForEach(device.modes) { mode in
                let selected = device.mode == mode
                Button { if !selected { send(.mode(mode)) } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: mode.symbol).font(.system(size: 13))
                        Text(mode.title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .foregroundStyle(selected ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
                    .background(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.06)), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("\(mode.title) mode")
                .accessibilityLabel("\(mode.title) mode")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func settingsGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func settingRow<Control: View>(_ title: String, _ symbol: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            Text(title)
            Spacer(minLength: 8)
            control()
        }
        .font(.callout)
        .frame(minHeight: 30)
    }

    /// A borderless value menu with native checkmarks, sized to its current value.
    private func optionMenu<Value: Hashable, Options: View>(_ title: String, selection: Binding<Value>,
                                                             @ViewBuilder options: () -> Options) -> some View {
        Menu {
            Picker(title, selection: selection) { options() }.pickerStyle(.inline).labelsHidden()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private var unsupportedMessage: String? {
        if !device.isSupported { return device.statusMessage ?? "Controls for this model aren't supported yet." }
        return "This unit doesn't report a target temperature."
    }

    @ViewBuilder private var powerButton: some View {
        if pending {
            ProgressView().controlSize(.small).frame(width: 30, height: 30)
        } else {
            Button { send(.power(!device.power)) } label: {
                Image(systemName: "power").font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(active ? AnyShapeStyle(.background) : AnyShapeStyle(.secondary))
                    .background(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.08)), in: Circle())
            }
            .buttonStyle(.plain).disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
            .help(device.power ? "Turn Off" : "Turn On")
            .accessibilityLabel(device.power ? "Turn off \(device.name)" : "Turn on \(device.name)")
        }
    }

    private func stepButton(_ symbol: String, label: String, value: Double) -> some View {
        let allowed = enabled && device.power && value >= device.minTemperature && value <= device.maxTemperature
        return Button { send(.temperature(value)) } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(!allowed)
        .foregroundStyle(allowed ? Color.primary : Color.secondary.opacity(0.5))
        .accessibilityLabel("\(label) for \(device.name)")
    }
}

private extension ACMode {
    var symbol: String {
        switch self {
        case .auto: return "a.circle"
        case .cool: return "snowflake"
        case .dry: return "drop"
        case .fan: return "fan"
        case .heat: return "sun.max"
        }
    }
}

private extension ACFeature {
    var symbol: String {
        switch self {
        case .eco: return "leaf"
        case .display: return "lightbulb"
        case .beep: return "speaker.wave.2"
        }
    }
}


private struct EnergyChart: View {
    let report: EnergyReport

    private struct Bar: Identifiable {
        let id: String
        let label: String
        let kWh: Double?
        let isToday: Bool
    }

    /// One bar per day in the window, so missing days show as gaps rather than zeros.
    private var bars: [Bar] {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let start = parser.date(from: report.start) else { return [] }
        let calendar = Calendar.current
        let values = Dictionary(report.days.map { ($0.date, $0.kWh) }, uniquingKeysWith: { $1 })
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = parser.string(from: date)
            return Bar(id: key, label: date.formatted(.dateTime.weekday(.narrow)), kWh: values[key], isToday: key == report.today)
        }
    }

    var body: some View {
        let bars = bars
        let peak = max(bars.compactMap(\.kWh).max() ?? 0, 0.01)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(bars) { bar in
                VStack(spacing: 4) {
                    GeometryReader { proxy in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(bar.isToday ? Color.primary : Color.primary.opacity(0.25))
                                .frame(height: bar.kWh.map { max(2, proxy.size.height * $0 / peak) } ?? 0)
                        }
                    }
                    Text(bar.label)
                        .foregroundStyle(bar.isToday ? .primary : .secondary)
                        .fontWeight(bar.isToday ? .semibold : .regular)
                }
                .frame(maxWidth: .infinity)
                .help(bar.kWh.map { "\(bar.id): \($0.formatted(.number.precision(.fractionLength(2)))) kWh" } ?? "\(bar.id): no reading")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(bar.id)
                .accessibilityValue(bar.kWh.map { "\($0.formatted(.number.precision(.fractionLength(2)))) kilowatt hours" } ?? "No reading")
            }
        }
        .frame(height: 64)
        .animation(.snappy, value: report.fetchedAt)
    }
}
