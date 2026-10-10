import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    enum RuntimeMode: String, CaseIterable, Identifiable {
        case localDemo, remote
        var id: String { rawValue }
        var title: String { self == .localDemo ? "Demo local" : "Servidor" }
    }

    @Published var runtimeMode: RuntimeMode {
        didSet { UserDefaults.standard.set(runtimeMode.rawValue, forKey: "dlc.runtime-mode") }
    }
    @Published var currentUser: AppUser?
    @Published var selectedBranch: Branch?
    @Published private(set) var remoteIdentity: RemoteIdentity?
    @Published private(set) var remoteCapabilities: RemoteCapabilities?
    @Published private(set) var remoteError = ""
    @Published private(set) var isRestoringRemoteSession = false

    let repository: MockRepository
    let remoteOfflineStore = RemoteOfflineStore()
    private(set) var remotePumpRepository: RemotePumpRepository?
    private(set) var remoteBranchRepository: RemoteBranchRepository?
    private(set) var remoteTankRepository: RemoteTankRepository?
    private(set) var remoteCutRepository: RemoteCutRepository?
    private(set) var remoteMetricsClient: RemoteAPIClient?
    private let remoteClient: RemoteAPIClient?
    private let remoteSessionStore = RemoteSessionStore()
    private var cancellables = Set<AnyCancellable>()

    init() {
        let storedMode = UserDefaults.standard.string(forKey: "dlc.runtime-mode")
        self.runtimeMode = RuntimeMode(rawValue: storedMode ?? "") ?? .localDemo
        self.repository = .shared
        let configured = (Bundle.main.object(forInfoDictionaryKey: "DLC_API_BASE_URL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURLString = configured.flatMap { $0.isEmpty ? nil : $0 } ?? "http://127.0.0.1:4000"
        let baseURL = URL(string: baseURLString) ?? URL(string: "http://127.0.0.1:4000")!
        let client = try? RemoteAPIClient(baseURL: baseURL)
        self.remoteClient = client
        self.remoteMetricsClient = client
        self.remotePumpRepository = client.map { APIRemotePumpRepository(client: $0) }
        self.remoteBranchRepository = client.map { APIRemoteBranchRepository(client: $0) }
        self.remoteTankRepository = client.map { APIRemoteTankRepository(client: $0) }
        self.remoteCutRepository = client.map { APIRemoteCutRepository(client: $0) }
        repository.$users
            .sink { [weak self] users in
                guard let self else { return }
                self.refreshActiveSession(users: users, branches: self.repository.branches)
            }
            .store(in: &cancellables)
        repository.$branches
            .sink { [weak self] branches in
                guard let self else { return }
                self.refreshActiveSession(users: self.repository.users, branches: branches)
            }
            .store(in: &cancellables)
    }

    func login(username: String, password: String) -> Bool {
        guard runtimeMode == .localDemo else { return false }
        guard repository.recoveryRequiredMessage == nil else { return false }
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let user = repository.authenticate(username: cleanUsername, password: password) else { return false }

        currentUser = nil
        selectedBranch = nil
        if user.role == .branchManager {
            guard let branchID = user.branchID, let branch = repository.branch(withID: branchID) else { return false }
            selectedBranch = branch
        }
        currentUser = user
        return true
    }

    func setRuntimeMode(_ mode: RuntimeMode) {
        guard currentUser == nil, remoteIdentity == nil else { return }
        runtimeMode = mode
        remoteError = ""
    }

    func loginRemote(email: String, password: String) async throws {
        guard runtimeMode == .remote, let remoteClient else { throw RemoteAPIError.invalidBaseURL }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            throw RemoteAPIError.http(status: 400, code: "VALIDATION", message: "Ingresa correo y contraseña.", correlationId: nil)
        }
        remoteError = ""
        do {
            let identity = try await remoteClient.authenticate(email: normalizedEmail, password: password)
            guard !identity.roles.isEmpty else {
                remoteSessionStore.clear()
                throw RemoteAPIError.http(status: 403, code: "NO_ROLE", message: "La cuenta no tiene un rol activo asignado.", correlationId: nil)
            }
            remoteIdentity = identity
            remoteCapabilities = try await remoteClient.capabilities(branchId: capabilityBranchID(for: identity))
        } catch {
            remoteSessionStore.clear()
            remoteIdentity = nil
            remoteCapabilities = nil
            throw error
        }
    }

    func restoreRemoteSession() async {
        guard runtimeMode == .remote, remoteIdentity == nil, let remoteClient,
              let tokens = remoteSessionStore.load(), !isRestoringRemoteSession else { return }
        isRestoringRemoteSession = true
        defer { isRestoringRemoteSession = false }
        do {
            if tokens.accessExpiresAt <= Date().addingTimeInterval(30) { _ = try await remoteClient.refreshSession() }
            let identity = try await remoteClient.currentIdentity()
            guard !identity.roles.isEmpty else { remoteSessionStore.clear(); return }
            remoteIdentity = identity
            remoteCapabilities = try await remoteClient.capabilities(branchId: capabilityBranchID(for: identity))
        } catch {
            remoteError = error.localizedDescription
            if let apiError = error as? RemoteAPIError,
               case .http(let status, _, _, _) = apiError, status == 401 { remoteSessionStore.clear() }
        }
    }

    func logoutRemote() async {
        do { try await remoteClient?.logout() }
        catch { remoteSessionStore.clear() }
        remoteIdentity = nil
        remoteCapabilities = nil
        remoteError = ""
    }

    private func capabilityBranchID(for identity: RemoteIdentity) -> UUID? {
        guard !identity.roles.contains(where: \.isGeneralManager) else { return nil }
        return identity.roles.first(where: { $0.branchId != nil })?.branchId
    }

    func logout() {
        currentUser = nil
        selectedBranch = nil
        if remoteIdentity != nil { Task { await logoutRemote() } }
    }

    private func refreshActiveSession(users: [AppUser], branches: [Branch]) {
        guard let signedInUser = currentUser else { return }
        guard let activeUser = users.first(where: { $0.id == signedInUser.id && $0.isActive }),
              activeUser.role == signedInUser.role else {
            logout()
            return
        }

        if activeUser.role == .branchManager {
            // A live reassignment changes the user's authority. Require a new
            // login so the active screen cannot silently switch branch scope.
            guard activeUser.branchID == signedInUser.branchID,
                  let branchID = activeUser.branchID,
                  let activeBranch = branches.first(where: { $0.id == branchID && $0.isActive }) else {
                logout()
                return
            }
            selectedBranch = activeBranch
        } else {
            selectedBranch = nil
        }
        currentUser = activeUser
    }
}
