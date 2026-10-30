// HyperLLM — трей-демон: держит mlx_lm.server с выбранной моделью на 127.0.0.1:8765.
import AppKit
import ServiceManagement

let port = 8765
let home = NSHomeDirectory()
let serverBin = home + "/.local/bin/mlx_lm.server"
let logURL = URL(fileURLWithPath: home + "/Library/Logs/HyperLLM/server.log")
let qwenWhisperHF = home + "/Library/Caches/QwenWhisper/Models"
let defaultHF = ProcessInfo.processInfo.environment["HF_HOME"] ?? home + "/.cache/huggingface"

struct Model { let id, title, size: String }
let models = [
    Model(id: "mlx-community/Qwen2.5-Coder-0.5B-4bit", title: "Qwen2.5 Coder 0.5B — быстрая", size: "290 МБ"),
    Model(id: "mlx-community/Qwen2.5-Coder-1.5B-4bit", title: "Qwen2.5 Coder 1.5B — точнее", size: "880 МБ"),
    Model(id: "mlx-community/Qwen3.5-2B-4bit", title: "Qwen3.5 2B (как в QwenWhisper)", size: "1.6 ГБ"),
]

func snapshots(_ id: String, _ hf: String) -> String {
    "\(hf)/hub/models--\(id.replacingOccurrences(of: "/", with: "--"))/snapshots"
}

// ponytail: «скачана» = есть config.json и хоть один .safetensors; битые шарды всплывут ошибкой сервера в логе.
func isCached(_ id: String, _ hf: String) -> Bool {
    let fm = FileManager.default
    let root = snapshots(id, hf)
    for snap in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
        let files = (try? fm.contentsOfDirectory(atPath: "\(root)/\(snap)")) ?? []
        if files.contains("config.json") && files.contains(where: { $0.hasSuffix(".safetensors") }) { return true }
    }
    return false
}

// Берём кэш QwenWhisper, если модель уже там, — не качаем второй раз.
func hfHome(_ id: String) -> String { isCached(id, qwenWhisperHF) ? qwenWhisperHF : defaultHF }

enum State: Equatable { case paused, downloading, starting, running, failed(String) }

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var proc: Process?
    var state = State.paused { didSet { render() } }
    var modelID = UserDefaults.standard.string(forKey: "model") ?? models[0].id

    func applicationDidFinishLaunching(_ n: Notification) {
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        menu.delegate = self
        item.menu = menu
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        start()
    }

    // Не ждём выхода: waitUntilExit внутри terminate: может зависнуть, а сторож и так добьёт сервер за ~1 с.
    func applicationWillTerminate(_ n: Notification) { stop() }

    // Запуск через sh-сторожа: он гасит дочерний процесс, если HyperLLM умер даже по kill -9.
    func spawn(_ args: [String], env: [String: String], onExit: @escaping (Int32) -> Void) {
        let guardScript = """
        "$@" & c=$!
        trap 'kill $c 2>/dev/null' TERM INT
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null && kill -0 $c 2>/dev/null; do sleep 1; done
        kill $c 2>/dev/null; wait $c
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", guardScript, "sh"] + args
        p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        let log = try? FileHandle(forWritingTo: logURL)
        if let log, log.seekToEndOfFile() > 5_000_000 { log.truncateFile(atOffset: 0) }  // сервер пишет на каждый запрос
        p.standardOutput = log ?? FileHandle.nullDevice
        p.standardError = log ?? FileHandle.nullDevice
        p.terminationHandler = { p in
            DispatchQueue.main.async {
                if self.proc === p { self.proc = nil }  // старый процесс не должен обнулить новый (смена модели)
                onExit(p.terminationStatus)
            }
        }
        do { try p.run(); proc = p } catch { state = .failed(error.localizedDescription) }
    }

    func start() {
        guard proc == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: serverBin) else {
            state = .failed("Нет mlx-lm: uv tool install --python 3.12 mlx-lm"); return
        }
        let id = modelID, hf = hfHome(id)
        if !isCached(id, hf) { download(id, hf); return }
        state = .starting
        spawn([serverBin, "--model", id, "--host", "127.0.0.1", "--port", "\(port)"],
              env: ["HF_HOME": hf, "HF_HUB_OFFLINE": "1"]) { [weak self] code in
            guard let self else { return }
            if case .paused = self.state { return }  // это мы его остановили
            self.state = .failed("Сервер упал (код \(code)) — см. лог")
        }
    }

    func download(_ id: String, _ hf: String) {
        state = .downloading
        let python = (serverBin as NSString).resolvingSymlinksInPath
            .replacingOccurrences(of: "/mlx_lm.server", with: "/python")
        spawn([python, "-c", "import sys; from huggingface_hub import snapshot_download; snapshot_download(sys.argv[1])", id],
              env: ["HF_HOME": hf]) { [weak self] code in
            guard let self else { return }
            if case .paused = self.state { return }
            if code == 0 { self.start() } else { self.state = .failed("Не скачалась (код \(code)) — см. лог") }
        }
    }

    func stop() {
        state = .paused
        proc?.terminate()
    }

    func poll() {
        guard state == .starting || state == .running else { return }
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/models")!)
        req.timeoutInterval = 1
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                guard self.proc != nil, self.state == .starting || self.state == .running else { return }
                self.state = ok ? .running : .starting
            }
        }.resume()
    }

    @objc func toggle() { proc == nil ? start() : stop() }

    @objc func pick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, id != modelID else { return }
        modelID = id
        UserDefaults.standard.set(id, forKey: "model")
        guard let p = proc else { start(); return }
        stop()
        DispatchQueue.global().async { p.waitUntilExit(); DispatchQueue.main.async { self.start() } }
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        do { try s.status == .enabled ? s.unregister() : s.register() } catch { state = .failed("Автозапуск: \(error.localizedDescription)") }
    }

    @objc func openLog() { NSWorkspace.shared.open(logURL) }

    func render() {
        let (icon, text): (String, String)
        switch state {
        case .paused: (icon, text) = ("⚪️", "На паузе")
        case .downloading: (icon, text) = ("⬇️", "Скачивается модель…")
        case .starting: (icon, text) = ("🟡", "Загружается…")
        case .running: (icon, text) = ("🟢", "Работает · 127.0.0.1:\(port)")
        case .failed(let msg): (icon, text) = ("🔴", msg)
        }
        item.button?.title = icon + " ⌨︎"
        item.button?.toolTip = "HyperLLM: " + text
    }

    // Меню собираем при открытии — галочки «скачана» и автозапуск всегда актуальны.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: item.button?.toolTip ?? "", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: proc == nil ? "Запустить" : "Пауза", action: #selector(toggle), keyEquivalent: "p").target = self

        let sub = NSMenu()
        for m in models {
            let mi = sub.addItem(withTitle: "\(m.title) · \(isCached(m.id, hfHome(m.id)) ? "скачана" : m.size)",
                                 action: #selector(pick), keyEquivalent: "")
            mi.target = self
            mi.representedObject = m.id
            mi.state = m.id == modelID ? .on : .off
        }
        menu.addItem(withTitle: "Модель", action: nil, keyEquivalent: "").submenu = sub

        let login = menu.addItem(withTitle: "Запускать при входе", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(withTitle: "Открыть лог", action: #selector(openLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
// kill/logout шлют SIGTERM мимо applicationWillTerminate.
signal(SIGTERM, SIG_IGN)
let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigterm.setEventHandler { app.terminate(nil) }
sigterm.resume()
app.run()
