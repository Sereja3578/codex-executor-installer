import AppKit
import Security
import SwiftUI

private let keychainService = "openai-tunnel-client-codex-executor"
private let tunnelPattern = try! NSRegularExpression(pattern: "^tunnel_[a-z0-9_]{20,100}$")

private struct CommandResult {
    let code: Int32
    let output: String
}

private func command(_ executable: String, _ arguments: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    do {
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(code: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    } catch {
        return CommandResult(code: 127, output: error.localizedDescription)
    }
}

private func firstExecutable(_ paths: [String]) -> String? {
    paths.first { FileManager.default.isExecutableFile(atPath: $0) }
}

private func brewPath() -> String? {
    firstExecutable(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"])
}

private func pythonPath() -> String? {
    firstExecutable(["/opt/homebrew/bin/python3.13", "/usr/local/bin/python3.13", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"])
}

private func codexPath() -> String? {
    firstExecutable(["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/Applications/ChatGPT.app/Contents/Resources/codex"])
}

private func tunnelClientPath() -> String? {
    firstExecutable(["/opt/homebrew/bin/tunnel-client", "/usr/local/bin/tunnel-client"])
}

private func openInBrowser(_ address: String) {
    guard let url = URL(string: address) else { return }
    NSWorkspace.shared.open(url)
}

private func keychainHasKey() -> Bool {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: NSUserName(),
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecReturnData as String: true
    ]
    var item: CFTypeRef?
    return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
}

private func saveKey(_ value: String) -> OSStatus {
    let data = Data(value.utf8)
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: NSUserName()
    ]
    if keychainHasKey() {
        return SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    }
    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(attributes as CFDictionary, nil)
}

private func launchTerminalTask(_ lines: [String]) -> Bool {
    let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Codex Executor Installer", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appendingPathComponent("install-dependencies.command")
        let body = "#!/bin/bash\nset -e\n" + lines.joined(separator: "\n") + "\necho 'Installation finished. Return to Codex Executor Installer and choose Check.'\n"
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return command("/usr/bin/open", ["-a", "Terminal", script.path]).code == 0
    } catch {
        return false
    }
}

struct InstallerView: View {
    @State private var tunnelID = ""
    @State private var runtimeKey = ""
    @State private var status = "Нажмите «Проверить Mac», чтобы начать."
    @State private var busy = false
    @State private var hasBrew = false
    @State private var hasPython = false
    @State private var hasCodex = false
    @State private var hasTunnelClient = false
    @State private var codexSignedIn = false
    @State private var keySaved = false

    private var resources: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Executor", isDirectory: true)
    }

    private var validTunnelID: Bool {
        let range = NSRange(tunnelID.startIndex..<tunnelID.endIndex, in: tunnelID)
        return tunnelPattern.firstMatch(in: tunnelID, range: range) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Codex Executor").font(.largeTitle).bold()
                Text("Установка на этом Mac — без копирования чужих ключей и истории задач.")
                    .foregroundStyle(.secondary)

                GroupBox("1. Подготовка Mac") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Homebrew: \(mark(hasBrew))   Python: \(mark(hasPython))   Codex: \(mark(hasCodex))   Tunnel: \(mark(hasTunnelClient))")
                        Text("Вход в Codex: \(mark(codexSignedIn))")
                        HStack {
                            Button("Проверить Mac", action: checkMac).disabled(busy)
                            Button("Установить недостающее через Homebrew", action: installDependencies)
                                .disabled(busy || (hasBrew && hasPython && hasCodex && hasTunnelClient))
                        }
                        Text("Перед установкой любых пакетов будет отдельное подтверждение. Отказ остановит этот этап.")
                            .font(.caption).foregroundStyle(.secondary)
                        if hasCodex && !codexSignedIn {
                            Button("Открыть вход в Codex", action: openCodexLogin)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("2. Личный туннель") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Создайте отдельный туннель для этого Mac. Ключ не вводите в чат и не сохраняйте в проект.")
                        Button("Открыть инструкцию OpenAI", action: {
                            openInBrowser("https://developers.openai.com/api/docs/guides/secure-mcp-tunnels")
                        })
                        TextField("Tunnel ID: tunnel_…", text: $tunnelID)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Runtime key", text: $runtimeKey)
                            .textFieldStyle(.roundedBorder)
                        Text("Ключ в Связке ключей: \(mark(keySaved))")
                        Button("Сохранить ключ в Связке ключей", action: storeRuntimeKey)
                            .disabled(runtimeKey.isEmpty || busy)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("3. Установить и проверить") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Установить Executor", action: installExecutor)
                            .disabled(busy || !readyToInstall)
                        HStack {
                            Button("Исправить автозапуск", action: repairService).disabled(busy)
                            Button("Обновить Executor", action: upgradeExecutor).disabled(busy)
                        }
                        Button("Проверить службу", action: checkService).disabled(busy)
                        Text("Для работы с защищёнными папками macOS может попросить отдельное разрешение. Полный доступ к диску для обычной установки не нужен.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Открыть настройки доступа к диску", action: {
                            openInBrowser("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
                        })
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("4. Подключить в ChatGPT") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("После успешной проверки откройте ChatGPT → Plugins → Add custom MCP server → Tunnel. Выберите туннель этого Mac и установите плагин в чат.")
                        Button("Открыть инструкцию подключения", action: {
                            openInBrowser("https://developers.openai.com/api/docs/guides/custom-mcp-server")
                        })
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(status).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(.quaternary.opacity(0.4)).cornerRadius(8)
            }.padding(24)
        }.frame(minWidth: 690, minHeight: 650)
        .onAppear {
            keySaved = keychainHasKey()
            checkMac()
        }
    }

    private var readyToInstall: Bool {
        hasBrew && hasPython && hasCodex && hasTunnelClient && codexSignedIn && keySaved && validTunnelID
    }

    private func mark(_ value: Bool) -> String { value ? "✓" : "—" }

    private func checkMac() {
        busy = true
        status = "Проверяю установленные компоненты…"
        DispatchQueue.global(qos: .userInitiated).async {
            let brew = brewPath() != nil
            let python = pythonPath() != nil
            let codex = codexPath()
            let tunnel = tunnelClientPath() != nil
            let signedIn = codex.map { command($0, ["login", "status"]).code == 0 } ?? false
            DispatchQueue.main.async {
                hasBrew = brew
                hasPython = python
                hasCodex = codex != nil
                hasTunnelClient = tunnel
                codexSignedIn = signedIn
                keySaved = keychainHasKey()
                status = brew && python && codex != nil && tunnel && signedIn
                    ? "Mac подготовлен. Теперь укажите отдельный туннель и сохраните его ключ."
                    : "Есть недостающие компоненты или требуется вход в Codex. Установите их и повторите проверку."
                busy = false
            }
        }
    }

    private func confirm(_ title: String, _ explanation: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = explanation
        alert.addButton(withTitle: "Продолжить")
        alert.addButton(withTitle: "Отмена")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func installDependencies() {
        let needsBrew = !hasBrew
        let needsPython = !hasPython
        let needsCodex = !hasCodex
        let needsTunnel = !hasTunnelClient
        let list = [needsBrew ? "Homebrew" : nil, needsPython ? "Python" : nil,
                    needsCodex ? "Codex CLI" : nil, needsTunnel ? "tunnel-client" : nil]
            .compactMap { $0 }.joined(separator: ", ")
        guard confirm("Установить: \(list)?", "Откроется Terminal с официальными командами установки. macOS может запросить пароль администратора. Без этих компонентов установка Executor не продолжится.") else {
            status = "Установка компонентов отменена. Продолжение заблокировано."
            return
        }
        var lines: [String] = []
        if needsBrew {
            lines.append("/bin/bash -c \"$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
        }
        lines.append("BREW=$(command -v brew || true)")
        lines.append("if [ -z \"$BREW\" ]; then BREW=/opt/homebrew/bin/brew; fi")
        lines.append("if [ ! -x \"$BREW\" ]; then BREW=/usr/local/bin/brew; fi")
        lines.append("if [ ! -x \"$BREW\" ]; then echo 'Homebrew installation failed'; exit 1; fi")
        if needsPython { lines.append("\"$BREW\" install python@3.13") }
        if needsTunnel { lines.append("\"$BREW\" install openai/tools/tunnel-client") }
        if needsCodex { lines.append("\"$BREW\" install --cask codex") }
        status = launchTerminalTask(lines)
            ? "Команды открыты в Terminal. После их завершения нажмите «Проверить Mac»."
            : "Не удалось открыть Terminal; установка не продолжена."
    }

    private func openCodexLogin() {
        guard let codex = codexPath() else { return }
        guard confirm("Войти в Codex?", "Откроется Terminal для входа в ваш аккаунт. Данные входа не проходят через установщик.") else { return }
        status = launchTerminalTask(["\"\(codex)\" login"])
            ? "После входа нажмите «Проверить Mac»."
            : "Не удалось открыть окно входа."
    }

    private func storeRuntimeKey() {
        guard confirm("Сохранить ключ?", "Ключ будет храниться только в Связке ключей этого Mac. Установщик не добавит его в файлы проекта.") else { return }
        let result = saveKey(runtimeKey.trimmingCharacters(in: .whitespacesAndNewlines))
        if result == errSecSuccess {
            runtimeKey = ""
            keySaved = true
            status = "Ключ сохранён в Связке ключей."
        } else {
            status = "Связка ключей не приняла ключ (код \(result)). Установка остановлена."
        }
    }

    private func installExecutor() {
        guard let python = pythonPath(), let codex = codexPath(),
              let tunnel = tunnelClientPath(), let source = resources else { return }
        let script = source.appendingPathComponent("install/portable.py").path
        guard FileManager.default.fileExists(atPath: script) else {
            status = "Установочный пакет неполон: отсутствует portable.py."
            return
        }
        guard confirm("Установить Codex Executor?", "Будут созданы локальная рабочая копия и одна служба автозапуска этого пользователя. Существующая установка не перезаписывается.") else { return }
        busy = true
        status = "Устанавливаю Executor…"
        let id = tunnelID
        DispatchQueue.global(qos: .userInitiated).async {
            let result = command(python, [script, "install", "--tunnel-id", id,
                                          "--tunnel-client", tunnel, "--codex-cli", codex,
                                          "--python-executable", python])
            DispatchQueue.main.async {
                status = result.code == 0
                    ? "Executor установлен. Нажмите «Проверить службу», затем подключите туннель в ChatGPT."
                    : "Установка не завершена (код \(result.code)): \(result.output.prefix(1000))"
                busy = false
            }
        }
    }

    private func checkService() {
        guard let python = pythonPath(), let source = resources else {
            status = "Python или установочный пакет не найден."
            return
        }
        busy = true
        status = "Проверяю службу…"
        let script = source.appendingPathComponent("install/portable.py").path
        DispatchQueue.global(qos: .userInitiated).async {
            let result = command(python, [script, "doctor"])
            DispatchQueue.main.async {
                status = result.code == 0
                    ? "Локальная служба работает. Это ещё не проверка вызова из ChatGPT — подключите плагин и выполните пробный вызов."
                    : "Служба пока не готова: \(result.output.prefix(1000))"
                busy = false
            }
        }
    }

    private func repairService() {
        runMaintenance("repair", title: "Исправить автозапуск?",
                       explanation: "Будет зарегистрирована уже установленная служба. Код и история задач не заменяются.")
    }

    private func upgradeExecutor() {
        runMaintenance("upgrade", title: "Обновить Executor?",
                       explanation: "Обновление остановится, если есть незавершённые задачи. Старый код будет сохранён отдельно для отката; история задач не удаляется.")
    }

    private func runMaintenance(_ action: String, title: String, explanation: String) {
        guard let python = pythonPath(), let source = resources else {
            status = "Python или установочный пакет не найден."
            return
        }
        guard confirm(title, explanation) else { return }
        let script = source.appendingPathComponent("install/portable.py").path
        busy = true
        status = action == "repair" ? "Исправляю автозапуск…" : "Обновляю Executor…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = command(python, [script, action])
            DispatchQueue.main.async {
                status = result.code == 0
                    ? "Готово. Нажмите «Проверить службу»."
                    : "Операция не завершена (код \(result.code)): \(result.output.prefix(1000))"
                busy = false
            }
        }
    }
}

@main
struct CodexExecutorInstaller: App {
    var body: some Scene {
        WindowGroup { InstallerView() }
    }
}
