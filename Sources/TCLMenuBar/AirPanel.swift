import SwiftUI
import AppKit
import Combine
import TCLCore

struct AirPanel: View {
    @ObservedObject var store: AppStore
    @StateObject private var launchAtLogin = LaunchAtLogin()
    @State private var contentHeight: CGFloat?
    @State private var headerHeight: CGFloat?
    @AppStorage("selectedDeviceID") private var selectedDeviceID = ""
    private let poll = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            // An explicit height lets MenuBarExtra size its window; scrolls past the cap.
            ScrollView {
                content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: contentHeight.map { min($0, 540) })
        }
        .frame(width: 380)
        .frame(maxHeight: .infinity, alignment: .top)
        .tint(.gray)
        .background(WindowTopAnchor(height: panelHeight))
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
        .onReceive(poll) { _ in
            if NSApplication.shared.keyWindow?.isVisible == true { Task { await store.refresh() } }
        }
    }

    private var panelHeight: CGFloat? {
        guard let headerHeight, let contentHeight else { return nil }
        return headerHeight + min(contentHeight, 540)
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
                if store.connectStep == nil {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
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
        if store.devices.count > 1 { DeviceSwitcher(devices: store.devices, selection: $selectedDeviceID) }
        if let device = store.devices.first(where: { $0.id == selectedDeviceID }) ?? store.devices.first {
            DeviceCard(energyStore: store, device: device, pending: store.pendingDevices.contains(device.id),
                       unconfirmed: store.unconfirmedDevices.contains(device.id), busy: store.busy) { command in
                Task { await store.send(command, to: device) }
            }
            .id(device.id)
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
                BrandMark(size: 52)
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
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(.primary.opacity(0.08), lineWidth: 1.5)
                Circle().trim(from: 0, to: 0.22)
                    .stroke(.primary.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                Image(nsImage: MenuBarIcon.snowflake(size: 24, lineWidth: 1.5)).renderingMode(.template)
                    .foregroundStyle(.primary)
            }
            .frame(width: 56, height: 56)
            .onAppear { withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spinning = true } }
            .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text("Connecting to TCL Home").font(.system(size: 15, weight: .semibold))
                if !email.isEmpty { Text(email).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }

            VStack(alignment: .leading, spacing: 0) {
                stepRow(.signingIn, "Signing in to your account")
                Divider().padding(.leading, 30)
                stepRow(.findingDevices, "Finding your air conditioners")
            }
            .padding(.horizontal, 12)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))

            Button("Cancel", action: cancel)
                .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.vertical, 12)
        .animation(.snappy, value: step)
    }

    private func stepRow(_ row: ConnectStep, _ title: String) -> some View {
        let done = row.rawValue < step.rawValue, current = row == step
        return HStack(spacing: 10) {
            Group {
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18).background(.primary.opacity(0.1), in: Circle())
                } else if current {
                    ProgressView().controlSize(.small).scaleEffect(0.8)
                } else {
                    Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1).frame(width: 14, height: 14)
                }
            }
            .frame(width: 18, height: 18)
            Text(title).font(.callout).foregroundStyle(done || current ? .primary : .secondary)
            Spacer()
        }
        .frame(height: 38)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : current ? "In progress" : "Waiting")
    }
}

private struct DeviceCard: View {
    @ObservedObject var energyStore: AppStore
    @State private var showEnergy = false
    @State private var showControls = false
    let device: AirConditioner
    let pending: Bool
    let unconfirmed: Bool
    let busy: Bool
    let send: (ACCommand) -> Void
    private var enabled: Bool { device.isOnline && device.isSupported && !pending && !busy }
    /// Requested power state shown immediately while the cloud confirms it.
    @State private var requestedPower: Bool?
    private var shownPower: Bool { requestedPower ?? device.power }
    private var active: Bool { device.isOnline && device.statusMessage == nil && shownPower }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                powerButton
            }
            ACHero(running: active, speed: airflowSpeed, swinging: device.airflow(.vertical) == .swing,
                   readout: device.targetTemperature.map { String(format: "%.0f", $0) }, mode: device.mode)
            if device.isSupported, let target = device.targetTemperature {
                temperatureControl(target)
            } else if let message = unsupportedMessage {
                Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if device.isSupported && device.hasExtraControls {
                controlTiles
            }
            if device.isSupported && (device.hasExtraControls || device.isOnline) {
                VStack(alignment: .leading, spacing: 0) {
                    if device.isSupported && hasMoreControls {
                        sectionHeader("More", summary: nil, expanded: showControls) { showControls.toggle() }
                        if showControls { moreControls.padding(.bottom, 10).transition(.opacity) }
                    }
                    if device.isSupported && device.isOnline {
                        if hasMoreControls { Divider() }
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

    @State private var draftTemperature: Double?

    private var airflowSpeed: Double {
        switch device.fanSpeed {
        case .quiet, .low, .speed1: return 0.6
        case .mediumLow: return 0.8
        case .mediumHigh, .high: return 1.3
        case .turbo: return 1.7
        default: return 1
        }
    }

    private func temperatureControl(_ target: Double) -> some View {
        let shown = draftTemperature ?? target
        let canAdjust = enabled && device.power
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(shown, specifier: "%.0f")")
                    .font(.system(size: 40, weight: .light)).monospacedDigit()
                    .contentTransition(.numericText(value: shown))
                Text("°C").font(.system(size: 16)).foregroundStyle(.secondary)
                Spacer()
                if let room = device.currentTemperature {
                    Label("\(room.formatted(.number.precision(.fractionLength(0))))°C", systemImage: "thermometer.medium")
                        .font(.caption).foregroundStyle(.secondary)
                        .help("Indoor temperature")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Target \(shown, specifier: "%.0f") degrees")
            HStack(spacing: 10) {
                stepButton("minus", label: "Lower temperature", value: target - 1)
                VStack(spacing: 2) {
                    Slider(value: Binding(get: { shown }, set: { draftTemperature = $0.rounded() }),
                           in: device.minTemperature...device.maxTemperature, step: 1) { editing in
                        if !editing, let value = draftTemperature {
                            if value != target { send(.temperature(value)) }
                            draftTemperature = nil
                        }
                    }
                    .controlSize(.small)
                    .tint(.primary)
                    .accessibilityLabel("Target temperature for \(device.name)")
                    HStack {
                        Text("\(device.minTemperature, specifier: "%.0f")°")
                        Spacer()
                        Text("\(device.maxTemperature, specifier: "%.0f")°")
                    }
                    .font(.caption2).foregroundStyle(.tertiary)
                }
                stepButton("plus", label: "Raise temperature", value: target + 1)
            }
            .disabled(!canAdjust)
        }
        .opacity(device.power ? 1 : 0.4)
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
        if unconfirmed { return "Not confirmed yet · refresh to check" }
        guard device.statusMessage == nil else { return "State unavailable" }
        let power = device.power ? "On" : "Off"
        guard let room = device.currentTemperature else { return power }
        return "\(power) · \(room.formatted(.number.precision(.fractionLength(0))))°C indoors"
    }

    private var controlsEnabled: Bool { enabled && device.power }

    private var hasMoreControls: Bool {
        device.supportsAirflow(.horizontal) || ACFeature.allCases.contains { device.feature($0) != nil }
    }

    /// Mode, fan, sleep and up/down airflow as four compact menu tiles.
    private var controlTiles: some View {
        HStack(spacing: 6) {
            if !device.modes.isEmpty {
                ControlTile(title: "Mode", value: device.mode?.title ?? "—", symbol: device.mode?.symbol ?? "a.circle",
                            selection: Binding<ACMode?>(get: { device.mode }, set: { if let value = $0, value != device.mode { send(.mode(value)) } })) {
                    ForEach(device.modes) { Label($0.title, systemImage: $0.symbol).tag(Optional($0)) }
                }
            }
            if !device.fanSpeeds.isEmpty {
                ControlTile(title: "Fan", value: device.fanSpeed?.title ?? "Custom", symbol: "fan",
                            selection: Binding<ACFanSpeed?>(get: { device.fanSpeed }, set: { if let value = $0 { send(.fan(value)) } })) {
                    ForEach(device.fanSpeeds) { Text($0.title).tag(Optional($0)) }
                }
                .disabled(device.mode == .dry)
            }
            if let sleep = device.sleep {
                ControlTile(title: "Sleep", value: sleep.title, symbol: "moon",
                            selection: Binding<ACSleep?>(get: { device.sleep }, set: { if let value = $0 { send(.sleep(value)) } })) {
                    ForEach(ACSleep.allCases) { Text($0.title).tag(Optional($0)) }
                }
                .disabled(device.mode != .cool && device.mode != .heat && sleep == .off)
            }
            if device.supportsAirflow(.vertical) {
                ControlTile(title: "Airflow", value: device.airflow(.vertical)?.title(for: .vertical) ?? "Custom", symbol: "wind",
                            selection: Binding<ACAirflow?>(get: { device.airflow(.vertical) }, set: { if let value = $0 { send(.airflow(.vertical, value)) } })) {
                    ForEach(ACAirflow.allCases) { Text($0.title(for: .vertical)).tag(Optional($0)) }
                }
            }
        }
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.4)
    }

    private var moreControls: some View {
        settingsGroup {
            if device.supportsAirflow(.horizontal) {
                settingRow(ACAxis.horizontal.title, "arrow.left.and.right") {
                    optionMenu(device.airflow(.horizontal)?.title(for: .horizontal) ?? "Custom",
                               selection: Binding<ACAirflow?>(get: { device.airflow(.horizontal) }, set: { if let value = $0 { send(.airflow(.horizontal, value)) } })) {
                        ForEach(ACAirflow.allCases) { Text($0.title(for: .horizontal)).tag(Optional($0)) }
                    }
                }
            }
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
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.4)
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

    private var powerButton: some View {
        Button {
            requestedPower = !shownPower
            send(.power(!device.power))
        } label: {
            Image(systemName: "power").font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(active ? AnyShapeStyle(.background) : AnyShapeStyle(.secondary))
                .background(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.08)), in: Circle())
                .overlay { if pending { PendingRing() } }
                .animation(.snappy, value: active)
        }
        .buttonStyle(.plain).disabled(!enabled)
        .opacity(enabled || pending ? 1 : 0.5)
        .help(pending ? "Waiting for the AC to confirm" : shownPower ? "Turn Off" : "Turn On")
        .accessibilityLabel(shownPower ? "Turn off \(device.name)" : "Turn on \(device.name)")
        .accessibilityValue(pending ? "Updating" : "")
        .onChange(of: pending) { _, isPending in if !isPending { requestedPower = nil } }
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


/// Equal-width unit picker shown when the account has more than one AC.
private struct DeviceSwitcher: View {
    let devices: [AirConditioner]
    @Binding var selection: String

    var body: some View {
        let current = devices.first { $0.id == selection }?.id ?? devices.first?.id
        HStack(spacing: 2) {
            ForEach(devices) { device in
                let selected = device.id == current
                Button { selection = device.id } label: {
                    HStack(spacing: 5) {
                        Circle().fill(device.isOnline && device.power ? Color.primary : Color.secondary.opacity(0.35))
                            .frame(width: 5, height: 5)
                        Text(device.name.replacingOccurrences(of: "Split ", with: "")).lineLimit(1)
                    }
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background(selected ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(device.name)
                .accessibilityLabel(device.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// A compact tile that opens a native menu of options.
private struct ControlTile<Value: Hashable, Options: View>: View {
    let title: String
    let value: String
    let symbol: String
    @Binding var selection: Value
    @ViewBuilder let options: () -> Options

    var body: some View {
        Menu {
            Picker(title, selection: $selection) { options() }.pickerStyle(.inline).labelsHidden()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 14))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.caption2).foregroundStyle(.secondary)
                    Text(value).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// Thin arc that orbits the power button while a command is in flight.
private struct PendingRing: View {
    @State private var spin = false
    var body: some View {
        Circle().trim(from: 0, to: 0.3)
            .stroke(.primary.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .padding(-4)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true } }
    }
}

/// Vector indoor unit with a louver, display and airflow. Powering on opens the louver,
/// lights the display and builds the airflow over about a second; powering off reverses it.
/// The airflow follows the mode: cool particles, wavy warm air, slower dry air.
private struct ACHero: View {
    let running: Bool
    var speed: Double = 1
    var swinging: Bool = false
    var readout: String?
    var mode: ACMode?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var changedAt = Date.distantPast
    @State private var transitioning = false

    private static let ramp = 1.1
    private static let streams = 11
    private static let wispsPerStream = 3

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || (!running && !transitioning))) { context in
            Canvas { canvas, size in draw(&canvas, size: size, now: context.date) } symbols: {
                Image(systemName: mode?.symbol ?? "a.circle")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .tag("mode")
            }
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .onChange(of: running) { _, _ in
            changedAt = .now
            transitioning = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.ramp + 0.1) { transitioning = false }
        }
    }

    private func draw(_ canvas: inout GraphicsContext, size: CGSize, now: Date) {
        let raw = reduceMotion ? 1 : min(1, now.timeIntervalSince(changedAt) / Self.ramp)
        let eased = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2
        let level = running ? eased : 1 - eased            // 0 = off, 1 = fully running
        let time = reduceMotion ? 0.6 : now.timeIntervalSinceReferenceDate
        let ink = Color.primary
        let dark = colorScheme == .dark
        let recess = Color.black.opacity(dark ? 0.42 : 0.16)

        let width = min(size.width * 0.64, 236), height: CGFloat = 68
        let unit = CGRect(x: (size.width - width) / 2, y: 4, width: width, height: height)
        let shell = Path(roundedRect: unit, cornerRadius: 6, style: .continuous)
        let seamY = unit.maxY - 24

        // Body: vertical shading, a darker lower panel below the seam, and a soft diagonal gloss.
        canvas.fill(shell, with: .linearGradient(Gradient(colors: [ink.opacity(0.12), ink.opacity(0.04)]),
                                                 startPoint: CGPoint(x: unit.midX, y: unit.minY), endPoint: CGPoint(x: unit.midX, y: unit.maxY)))
        canvas.drawLayer { layer in
            layer.clip(to: shell)
            layer.fill(Path(CGRect(x: unit.minX, y: seamY, width: width, height: unit.maxY - seamY)), with: .color(.black.opacity(dark ? 0.12 : 0.04)))
            var gloss = Path()
            gloss.move(to: CGPoint(x: unit.minX + width * 0.08, y: unit.minY))
            gloss.addLine(to: CGPoint(x: unit.minX + width * 0.30, y: unit.minY))
            gloss.addLine(to: CGPoint(x: unit.minX + width * 0.18, y: seamY))
            gloss.addLine(to: CGPoint(x: unit.minX - width * 0.04, y: seamY))
            gloss.closeSubpath()
            layer.drawLayer { soft in
                soft.addFilter(.blur(radius: 6))
                soft.fill(gloss, with: .linearGradient(Gradient(colors: [ink.opacity(0.06), ink.opacity(0)]),
                                                       startPoint: CGPoint(x: unit.minX, y: unit.minY), endPoint: CGPoint(x: unit.minX + width * 0.3, y: seamY)))
            }
            var seam = Path()
            seam.move(to: CGPoint(x: unit.minX, y: seamY))
            seam.addLine(to: CGPoint(x: unit.maxX, y: seamY))
            layer.stroke(seam, with: .color(ink.opacity(0.10)), lineWidth: 1)
        }
        canvas.stroke(shell, with: .color(ink.opacity(0.22 + 0.22 * level)), lineWidth: 1)
        var highlight = Path()
        highlight.move(to: CGPoint(x: unit.minX + 7, y: unit.minY + 1.5))
        highlight.addLine(to: CGPoint(x: unit.maxX - 7, y: unit.minY + 1.5))
        canvas.stroke(highlight, with: .color(ink.opacity(0.14)), style: StrokeStyle(lineWidth: 1, lineCap: .round))

        // Display window: mode icon and target temperature, lit while running.
        let display = CGRect(x: unit.maxX - 60, y: unit.minY + 14, width: 42, height: 16)
        canvas.fill(Path(roundedRect: display, cornerRadius: 4, style: .continuous), with: .color(recess.opacity(0.6 + 0.4 * level)))
        var lit = canvas
        lit.opacity = 0.9 * level                          // blank when off
        if let symbol = canvas.resolveSymbol(id: "mode") { lit.draw(symbol, at: CGPoint(x: display.minX + 10.5, y: display.midY)) }
        if let readout {
            lit.draw(Text(readout).font(.system(size: 9.5, weight: .semibold).monospacedDigit()).foregroundStyle(ink),
                     at: CGPoint(x: display.maxX - 13.5, y: display.midY))
        }

        // Outlet and louver. Closed, the flap sits flush over the outlet; opening, it swings down,
        // uncovering the dark outlet and its vertical fins.
        let outlet = CGRect(x: unit.minX + 16, y: seamY + 6, width: width - 32, height: 11)
        let left = outlet.minX, right = outlet.maxX
        let flapTop = outlet.minY + outlet.height * level          // hinge line slides down as the flap opens
        let flapBottom = outlet.maxY + 10 * level                  // free edge swings below the unit
        let bow = 2.5 * level

        if level > 0.01 {
            let opening = CGRect(x: left, y: outlet.minY, width: outlet.width, height: flapTop - outlet.minY)
            canvas.fill(Path(roundedRect: opening, cornerRadius: 1.5), with: .color(recess.opacity(0.9)))
            // Fins: evenly spaced vertical vanes inside the outlet.
            var fins = Path()
            var x = left + 8
            while x < right - 6 {
                fins.move(to: CGPoint(x: x, y: opening.minY + 1.5))
                fins.addLine(to: CGPoint(x: x, y: opening.maxY - 0.5))
                x += 9
            }
            canvas.stroke(fins, with: .color(ink.opacity(0.16 * level)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }

        var flap = Path()
        flap.move(to: CGPoint(x: left, y: flapTop))
        flap.addLine(to: CGPoint(x: right, y: flapTop))
        flap.addLine(to: CGPoint(x: right, y: flapBottom))
        flap.addQuadCurve(to: CGPoint(x: left, y: flapBottom), control: CGPoint(x: (left + right) / 2, y: flapBottom + bow))
        flap.closeSubpath()
        canvas.fill(flap, with: .linearGradient(Gradient(colors: [ink.opacity(0.09), ink.opacity(0.05 + 0.06 * level)]),
                                                startPoint: CGPoint(x: 0, y: flapTop), endPoint: CGPoint(x: 0, y: flapBottom)))
        if level < 0.99 {
            // Closed seam around the flap, fading out as it opens.
            canvas.stroke(Path(roundedRect: CGRect(x: left, y: flapTop, width: right - left, height: max(flapBottom - flapTop, 1)), cornerRadius: 1.5),
                          with: .color(ink.opacity(0.14 * (1 - level))), lineWidth: 1)
        }
        var lip = Path()
        lip.move(to: CGPoint(x: right, y: flapBottom))
        lip.addQuadCurve(to: CGPoint(x: left, y: flapBottom), control: CGPoint(x: (left + right) / 2, y: flapBottom + bow))
        canvas.stroke(lip, with: .color(ink.opacity(0.15 + 0.5 * level)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

        guard level > 0.01 else { return }
        let top = flapBottom + bow + 2, depth = size.height - top - 2
        let sweep = swinging ? sin(time * 0.7) * 0.35 : 0.1
        let pace = speed * (mode == .dry ? 0.6 : 1)
        let waviness: Double = mode == .heat ? 7 : 3.5
        let strength: Double = mode == .dry ? 0.7 : mode == .fan ? 0.85 : 1

        // Soft glow of moving air beneath the vent.
        var cone = Path()
        cone.move(to: CGPoint(x: left + 4, y: top))
        cone.addLine(to: CGPoint(x: right - 4, y: top))
        cone.addLine(to: CGPoint(x: unit.midX + width * 0.64 + sweep * depth * 1.4, y: top + depth))
        cone.addLine(to: CGPoint(x: unit.midX - width * 0.64 + sweep * depth * 1.4, y: top + depth))
        cone.closeSubpath()
        canvas.drawLayer { glow in
            glow.addFilter(.blur(radius: 12))
            glow.fill(cone, with: .linearGradient(Gradient(colors: [ink.opacity(0.10 * level * strength), ink.opacity(0)]),
                                                  startPoint: CGPoint(x: unit.midX, y: top), endPoint: CGPoint(x: unit.midX, y: top + depth * 0.9)))
        }

        func point(_ t: Double, _ p: Double, _ seed: Double) -> CGPoint {
            let spread = t * (width / 2 - 22) + t * (p * 0.6 + p * p * 0.4) * width * 0.32
            let lean = sweep * p * depth * 1.4
            let sway = sin(time * (mode == .heat ? 2.6 : 1.6) + seed * 2.3 + p * (mode == .heat ? 7 : 4)) * waviness * p
            return CGPoint(x: unit.midX + spread + lean + sway, y: top + p * depth)
        }
        let reach = 0.35 + 0.65 * level                       // airflow extends further as it builds
        canvas.drawLayer { air in
        air.addFilter(.blur(radius: 0.7))
        for stream in 0..<Self.streams {
            let t = Double(stream) / Double(Self.streams - 1) * 2 - 1
            for wisp in 0..<Self.wispsPerStream {
                let seed = Double(stream * 7 + wisp * 13)
                let rate = 0.42 * pace * (0.85 + 0.3 * (sin(seed) * 0.5 + 0.5))
                let cycle = (time * rate + Double(wisp) / Double(Self.wispsPerStream) + sin(seed * 1.7) * 0.5)
                    .truncatingRemainder(dividingBy: 1)
                let head = cycle * reach, tail = max(0, head - 0.34 * reach)
                guard head > 0.02 else { continue }
                var path = Path()
                path.move(to: point(t, tail, seed))
                for step in 1...10 { path.addLine(to: point(t, tail + (head - tail) * Double(step) / 10, seed)) }
                let alpha = sin(.pi * cycle) * (0.42 - abs(t) * 0.12) * level * strength
                air.stroke(path, with: .linearGradient(Gradient(colors: [ink.opacity(0), ink.opacity(alpha), ink.opacity(alpha * 0.6)]),
                                                       startPoint: point(t, tail, seed), endPoint: point(t, head, seed)),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
            // Cool air: small particles drifting between the wisps.
            if mode == .cool && stream % 2 == 1 {
                for particle in 0..<2 {
                    let seed = Double(stream * 11 + particle * 5 + 3)
                    let cycle = (time * 0.3 * pace * (0.8 + 0.4 * (sin(seed) * 0.5 + 0.5)) + Double(particle) * 0.5 + cos(seed) * 0.3)
                        .truncatingRemainder(dividingBy: 1)
                    let p = cycle * reach
                    let center = point(t + sin(seed) * 0.08, p, seed + 1)
                    let radius = 0.8 + 0.6 * (cos(seed * 2.1) * 0.5 + 0.5)
                    air.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(ink.opacity(sin(.pi * cycle) * 0.5 * level)))
                }
            }
        }
        }
    }
}
