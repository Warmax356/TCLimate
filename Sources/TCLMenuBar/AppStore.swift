import SwiftUI
import TCLCore

enum ConnectStep: Int { case signingIn = 1, findingDevices }

@MainActor
final class AppStore: ObservableObject {
    @Published var devices: [AirConditioner] = []
    @Published var energyReports: [String: EnergyReport] = [:]
    @Published var energyErrors: [String: String] = [:]
    @Published var pendingEnergy: Set<String> = []
    @Published var connected = false
    @Published var busy = false
    @Published var pendingDevices: Set<String> = []
    @Published var error: String?
    @Published var notice: String?
    @Published var lastUpdated: Date?
    @Published var connectStep: ConnectStep?
    @Published var email = ""
    @Published var password = ""
    @Published var region: AccountRegion = .singapore
    @Published var remember = true
    private var client = CloudClient()
    private var generation = 0
    private var attemptedRestore = false

    func restore() async {
        guard !attemptedRestore else { await refresh(); return }
        attemptedRestore = true
        do {
            guard let login = try LoginKeychain.load() else { return }
            email = login.email
            region = login.region
            await connect(login: login, save: false)
        } catch { self.error = error.localizedDescription }
    }

    func signIn() async {
        guard !busy, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else { return }
        let login = SavedLogin(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, region: region)
        await connect(login: login, save: remember)
    }

    private func connect(login: SavedLogin, save: Bool) async {
        busy = true
        error = nil
        notice = nil
        let current = generation
        let candidate = CloudClient()
        connectStep = .signingIn
        do {
            try await candidate.login(email: login.email, password: login.password, region: login.region)
            guard current == generation else { return }
            connectStep = .findingDevices
            let found = try await candidate.devices()
            guard current == generation else { return }
            client = candidate
            devices = found
            connected = true
            lastUpdated = Date()
            password = ""
            do {
                if save { try LoginKeychain.save(login) }
                else if !remember { try LoginKeychain.delete() }
            } catch { self.error = "Connected, but sign-in could not be saved. \(error.localizedDescription)" }
        } catch {
            if current == generation { self.error = error.localizedDescription }
        }
        if current == generation { busy = false; connectStep = nil }
    }

    func cancelConnect() {
        guard connectStep != nil else { return }
        generation += 1
        connectStep = nil
        busy = false
    }

    func refresh() async {
        guard connected, !busy, pendingDevices.isEmpty else { return }
        busy = true
        let current = generation
        do {
            let found = try await client.devices()
            guard current == generation else { return }
            devices = found
            lastUpdated = Date()
            error = nil
            notice = nil
        } catch { if current == generation { self.error = error.localizedDescription } }
        if current == generation { busy = false }
    }

    func send(_ command: ACCommand, to device: AirConditioner) async {
        guard connected, !busy, !pendingDevices.contains(device.id), device.isOnline, device.isSupported else { return }
        pendingDevices.insert(device.id)
        error = nil
        notice = nil
        let current = generation
        let activeClient = client
        do {
            try await activeClient.control(device: device, command: command)
            guard current == generation else { return }
            notice = "Command sent. Waiting for the AC to report its state."
            try await Task.sleep(for: .seconds(2))
            let found = try await activeClient.devices()
            guard current == generation else { return }
            devices = found
            lastUpdated = Date()
            let reported = found.first { $0.id == device.id }
            let confirmed = reported?.confirms(command) == true
            notice = confirmed ? "\(device.name) confirmed the change." : "Command sent. The AC has not confirmed the change yet; refresh to check."
        } catch { if current == generation { self.error = error.localizedDescription } }
        if current == generation { pendingDevices.remove(device.id) }
    }

    func loadEnergy(for device: AirConditioner) async {
        guard connected, device.isOnline, !pendingEnergy.contains(device.id) else { return }
        let current = generation
        pendingEnergy.insert(device.id)
        energyErrors[device.id] = nil
        do {
            let report = try await client.energy(for: device)
            guard current == generation else { return }
            energyReports[device.id] = report
        } catch {
            if current == generation { energyErrors[device.id] = error.localizedDescription }
        }
        if current == generation { pendingEnergy.remove(device.id) }
    }

    func signOut() {
        guard !busy, pendingDevices.isEmpty else { return }
        do { try LoginKeychain.delete() }
        catch { self.error = error.localizedDescription; return }
        generation += 1
        client = CloudClient()
        connected = false
        devices = []
        energyReports = [:]
        energyErrors = [:]
        pendingEnergy = []
        password = ""
        lastUpdated = nil
        notice = nil
        error = nil
    }
}
