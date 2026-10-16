import SwiftUI
import AppKit

final class DriveDownloader: ObservableObject {
    struct SharedDrive: Codable, Hashable, Identifiable { let id: String; let name: String }
    struct InventoryEntry: Codable {
        let driveID: String
        let driveName: String
        let count: Int64
        let bytes: Int64
        let manifestPath: String
        let scannedAt: Date
    }
    struct ListedFile: Codable { let Path: String; let Size: Int64 }
    @Published var driveURL = ""
    @Published var destination = ""
    @Published var remotes: [String] = []
    @Published var selectedRemote = ""
    @Published var sharedDrives: [SharedDrive] = []
    @Published var selectedSharedDriveID = ""
    @Published var allSharedDrives = true
    @Published var selectedTypes: Set<String> = ["PDF"]
    @Published var output = "Listo. Conecta Google Drive o selecciona una conexión existente."
    @Published var progressSummary = "Primero escanea los PDF para calcular el total."
    @Published var isRunning = false
    private var process: Process?
    private var scannedTotalBytes: Int64 = 0
    private var scannedBytesByDrive: [String: Int64] = [:]
    private var scannedCountByDrive: [String: Int64] = [:]
    private var inventory: [String: InventoryEntry] = [:]

    let fileTypes = ["Todos", "PDF", "EXE", "Ebooks", "Documentos", "Comprimidos", "Imágenes", "Videos", "Audio"]

    init() { loadInventory() }

    private var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Descargador Drive", isDirectory: true)
    }

    private var inventoryURL: URL { supportDirectory.appendingPathComponent("inventario.json") }

    private func loadInventory() {
        guard let data = try? Data(contentsOf: inventoryURL),
              let saved = try? JSONDecoder().decode([String: InventoryEntry].self, from: data) else { return }
        inventory = saved
        scannedBytesByDrive = saved.mapValues(\.bytes)
        scannedCountByDrive = saved.mapValues(\.count)
        scannedTotalBytes = saved.values.reduce(0) { $0 + $1.bytes }
        if !saved.isEmpty {
            let total = saved.values.reduce(Int64(0)) { $0 + $1.count }
            progressSummary = "Inventario guardado: \(total.formatted()) PDF · \(formatBytes(scannedTotalBytes))"
        }
    }

    private func saveInventory() {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(inventory) { try? data.write(to: inventoryURL, options: .atomic) }
    }

    var rclonePath: String {
        Bundle.main.path(forResource: "rclone", ofType: nil) ?? ""
    }

    func refreshRemotes() {
        guard !rclonePath.isEmpty else { output = "No se encontró el motor rclone integrado."; return }
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: rclonePath)
        task.arguments = ["listremotes"]
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run(); task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let names = String(data: data, encoding: .utf8)?.split(separator: "\n").map(String.init) ?? []
            DispatchQueue.main.async {
                self.remotes = names
                if self.selectedRemote.isEmpty { self.selectedRemote = names.first ?? "" }
                if names.isEmpty { self.output = "Pulsa ‘Conectar Google Drive’. Se abrirá Google para autorizar tu cuenta." }
                else { self.loadSharedDrives() }
            }
        } catch { DispatchQueue.main.async { self.output = "Error: \(error.localizedDescription)" } }
    }

    func loadSharedDrives() {
        guard !selectedRemote.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process(), out = Pipe()
            task.executableURL = URL(fileURLWithPath: self.rclonePath)
            task.arguments = ["backend", "drives", self.selectedRemote, "--json"]
            task.standardOutput = out
            task.standardError = Pipe()
            do {
                try task.run(); task.waitUntilExit()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let drives = (try? JSONDecoder().decode([SharedDrive].self, from: data)) ?? []
                DispatchQueue.main.async {
                    self.sharedDrives = drives.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    if self.selectedSharedDriveID.isEmpty { self.selectedSharedDriveID = self.sharedDrives.first?.id ?? "" }
                }
            } catch { }
        }
    }

    func connectGoogle() {
        let name = "GoogleDrive"
        run(arguments: ["config", "create", name, "drive", "scope", "drive"], heading: "Conectando con Google Drive…\nCompleta la autorización en el navegador.\n") { [weak self] ok in
            if ok { self?.refreshRemotes() }
        }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Elegir carpeta"
        if panel.runModal() == .OK { destination = panel.url?.path ?? "" }
    }

    func toggleType(_ type: String) {
        if type == "Todos" {
            selectedTypes = selectedTypes.contains("Todos") ? [] : ["Todos"]
        } else {
            selectedTypes.remove("Todos")
            if selectedTypes.contains(type) { selectedTypes.remove(type) } else { selectedTypes.insert(type) }
        }
        clearScanCache()
    }

    private var isPDFOnly: Bool { selectedTypes == ["PDF"] }

    private func clearScanCache() {
        scannedTotalBytes = 0
        scannedBytesByDrive = [:]
        scannedCountByDrive = [:]
        inventory = [:]
        saveInventory()
        progressSummary = "Descargar detectará automáticamente dónde están los PDF."
    }

    func startDownload() {
        guard !selectedRemote.isEmpty else { output = "Primero conecta o selecciona Google Drive."; return }
        guard !destination.isEmpty else { output = "Selecciona una carpeta de destino."; return }
        guard !selectedTypes.isEmpty else { output = "Selecciona al menos un tipo de archivo."; return }
        if let values = try? URL(fileURLWithPath: destination).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = values.volumeAvailableCapacityForImportantUsage, free < 5_000_000_000 {
            output = "Espacio insuficiente: quedan menos de 5 GB libres. Libera espacio antes de descargar."
            return
        }
        let isSharedDrivesPage = allSharedDrives || driveURL.contains("/shared-drives")
        var jobs: [(String, String)] = []
        if isSharedDrivesPage && allSharedDrives {
            jobs = sharedDrives.map { ($0.id, safeFolderName($0.name)) }
            if isPDFOnly && !scannedCountByDrive.isEmpty {
                jobs = jobs.filter { (scannedCountByDrive[$0.0] ?? 0) > 0 }
            }
            guard !jobs.isEmpty else {
                output = scannedCountByDrive.isEmpty
                    ? "Pulsa Actualizar para detectar las unidades compartidas."
                    : "No se detectaron PDF en ninguna unidad compartida. No hay nada que descargar."
                return
            }
        } else if isSharedDrivesPage {
            guard let drive = sharedDrives.first(where: { $0.id == selectedSharedDriveID }) else { output = "Selecciona una unidad compartida."; return }
            jobs = [(drive.id, safeFolderName(drive.name))]
        } else {
            guard let folderID = extractFolderID(driveURL) else { output = "La URL no parece ser el enlace de una carpeta de Google Drive."; return }
            jobs = [(folderID, "Carpeta Google Drive")]
        }
        let skipped = allSharedDrives && isPDFOnly && !scannedCountByDrive.isEmpty ? max(0, sharedDrives.count - jobs.count) : 0
        output = "Preparando \(jobs.count) descarga(s). Unidades sin PDF omitidas: \(skipped).\n"
        runJobs(jobs, index: 0)
    }

    func scanPDFs() {
        guard !selectedRemote.isEmpty else { output = "Primero conecta Google Drive."; return }
        let targets: [SharedDrive]
        if allSharedDrives {
            targets = sharedDrives
        } else if let drive = sharedDrives.first(where: { $0.id == selectedSharedDriveID }) {
            targets = [drive]
        } else {
            output = "Selecciona una unidad compartida."
            return
        }
        guard !targets.isEmpty else { output = "Pulsa Actualizar para detectar las unidades compartidas."; return }
        isRunning = true
        output = "Escaneando PDF en \(targets.count) unidad(es)…\n"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var totalCount: Int64 = 0
            var totalBytes: Int64 = 0
            var bytesByDrive: [String: Int64] = [:]
            var countByDrive: [String: Int64] = [:]
            var newInventory: [String: InventoryEntry] = [:]
            for (index, drive) in targets.enumerated() {
                if !self.isRunning { break }
                DispatchQueue.main.async { self.output = "Escaneando unidad \(index + 1) de \(targets.count): \(drive.name)\nPDF encontrados hasta ahora: \(totalCount)\nTamaño acumulado: \(self.formatBytes(totalBytes))" }
                let task = Process(), out = Pipe()
                self.process = task
                task.executableURL = URL(fileURLWithPath: self.rclonePath)
                task.arguments = ["lsjson", self.selectedRemote, "--recursive", "--files-only", "--drive-root-folder-id", drive.id, "--filter", "+ *.[pP][dD][fF]", "--filter", "- *", "--fast-list"]
                task.standardOutput = out
                task.standardError = Pipe()
                do {
                    try task.run(); task.waitUntilExit()
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    if let files = try? JSONDecoder().decode([ListedFile].self, from: data) {
                        let driveCount = Int64(files.count)
                        let driveBytes = files.reduce(Int64(0)) { $0 + max(0, $1.Size) }
                        try? FileManager.default.createDirectory(at: self.supportDirectory, withIntermediateDirectories: true)
                        let manifest = self.supportDirectory.appendingPathComponent("pdf-\(drive.id).txt")
                        let paths = files.map(\.Path).joined(separator: "\n") + (files.isEmpty ? "" : "\n")
                        try? paths.write(to: manifest, atomically: true, encoding: .utf8)
                        totalCount += driveCount
                        totalBytes += driveBytes
                        bytesByDrive[drive.id] = driveBytes
                        countByDrive[drive.id] = driveCount
                        newInventory[drive.id] = InventoryEntry(driveID: drive.id, driveName: drive.name, count: driveCount, bytes: driveBytes, manifestPath: manifest.path, scannedAt: Date())
                    }
                } catch { }
            }
            DispatchQueue.main.async {
                self.process = nil
                let completed = self.isRunning
                self.isRunning = false
                if completed {
                    self.scannedTotalBytes = totalBytes
                    self.scannedBytesByDrive = bytesByDrive
                    self.scannedCountByDrive = countByDrive
                    self.inventory = newInventory
                    self.saveInventory()
                    self.progressSummary = "Descargado: 0 GB  ·  Falta: \(self.formatBytes(totalBytes))  ·  Total: \(self.formatBytes(totalBytes))"
                    let useful = countByDrive.values.filter { $0 > 0 }.count
                    self.output = "✅ DETECCIÓN COMPLETADA\n\nUnidades con PDF: \(useful) de \(targets.count)\nUnidades vacías omitidas: \(targets.count - useful)\nPDF detectados: \(totalCount.formatted())\nTamaño total: \(self.formatBytes(totalBytes))\nBytes exactos: \(totalBytes.formatted())"
                } else {
                    self.output += "\nEscaneo detenido."
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func runJobs(_ jobs: [(String, String)], index: Int) {
        guard index < jobs.count else {
            let catalog = buildRAGCatalog()
            output += "\n✅ TODAS LAS DESCARGAS COMPLETADAS\nCatálogo para RAG: \(catalog ?? "no se pudo crear")"
            return
        }
        let job = jobs[index]
        let jobDestination = jobs.count > 1 ? (destination as NSString).appendingPathComponent(job.1) : destination
        do {
            try FileManager.default.createDirectory(atPath: jobDestination, withIntermediateDirectories: true)
        } catch {
            output += "\nNo se pudo crear la carpeta de destino: \(error.localizedDescription)"
            return
        }
        var args = ["copy", selectedRemote, jobDestination, "--drive-root-folder-id", job.0]
        if !selectedTypes.contains("Todos") {
            for pattern in patterns() { args += ["--filter", "+ \(pattern)"] }
            args += ["--filter", "- *"]
        }
        if isPDFOnly, let entry = inventory[job.0], FileManager.default.fileExists(atPath: entry.manifestPath) {
            args += ["--files-from-raw", entry.manifestPath]
        }
        let log = (jobDestination as NSString).appendingPathComponent("descarga_google_drive.log")
        args += ["--progress", "--stats", "2s", "--stats-one-line", "--transfers", "8", "--checkers", "16", "--checksum", "--metadata", "--order-by", "size,ascending", "--drive-acknowledge-abuse", "--retries", "100", "--retries-sleep", "10s", "--low-level-retries", "100", "--contimeout", "30s", "--timeout", "5m", "--log-file", log, "--log-level", "INFO"]
        let completedBefore = jobs.prefix(index).reduce(Int64(0)) { $0 + (scannedBytesByDrive[$1.0] ?? 0) }
        run(arguments: args, heading: "Unidad \(index + 1) de \(jobs.count): \(job.1)\nDestino: \(jobDestination)\n\n", progressBase: completedBefore) { [weak self] ok in
            guard let self else { return }
            if ok { self.runJobs(jobs, index: index + 1) }
            else { self.output += "\n⚠️ Descarga detenida. Iníciala otra vez para continuar." }
        }
    }

    private func safeFolderName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    private func buildRAGCatalog() -> String? {
        guard !destination.isEmpty else { return nil }
        let root = URL(fileURLWithPath: destination)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        var rows = ["ruta,nombre,tamano_bytes,modificado,estado_rag"]
        let formatter = ISO8601DateFormatter()
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "pdf" {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let relative = String(url.path.dropFirst(min(root.path.count + 1, url.path.count)))
            func csv(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            rows.append([csv(relative), csv(url.deletingPathExtension().lastPathComponent), String(values?.fileSize ?? 0), formatter.string(from: values?.contentModificationDate ?? Date()), "pendiente_extraccion"].joined(separator: ","))
        }
        let catalog = root.appendingPathComponent("catalogo_rag_pdf.csv")
        do {
            try (rows.joined(separator: "\n") + "\n").write(to: catalog, atomically: true, encoding: .utf8)
            return catalog.path
        } catch { return nil }
    }

    func stop() {
        process?.interrupt()
        output += "\nDeteniendo descarga…"
    }

    private func run(arguments: [String], heading: String, progressBase: Int64 = 0, completion: @escaping (Bool) -> Void) {
        guard !isRunning else { return }
        output = heading
        isRunning = true
        let task = Process(), pipe = Pipe()
        process = task
        task.executableURL = URL(fileURLWithPath: rclonePath)
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.output += text
                self?.updateTransferProgress(text, base: progressBase)
            }
        }
        task.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.process = nil
                completion(proc.terminationStatus == 0)
            }
        }
        do { try task.run() }
        catch {
            isRunning = false
            output += "\nError: \(error.localizedDescription)"
            completion(false)
        }
    }

    private func updateTransferProgress(_ text: String, base: Int64) {
        guard scannedTotalBytes > 0 else { return }
        let pattern = #"Transferred:\s+([0-9.,]+)\s+([KMGTPE]?i?B)\s+/"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else { return }
        let numberText = String(text[numberRange]).replacingOccurrences(of: ",", with: "")
        guard let number = Double(numberText) else { return }
        let unit = String(text[unitRange]).uppercased()
        let powers: [String: Double] = ["B": 1, "KIB": 1024, "MIB": 1_048_576, "GIB": 1_073_741_824, "TIB": 1_099_511_627_776, "KB": 1000, "MB": 1_000_000, "GB": 1_000_000_000, "TB": 1_000_000_000_000]
        let current = Int64(number * (powers[unit] ?? 1))
        let downloaded = min(scannedTotalBytes, base + current)
        let remaining = max(0, scannedTotalBytes - downloaded)
        progressSummary = "Descargado: \(formatBytes(downloaded))  ·  Falta: \(formatBytes(remaining))  ·  Total: \(formatBytes(scannedTotalBytes))"
    }

    private func extractFolderID(_ text: String) -> String? {
        let patterns = [#"/folders/([A-Za-z0-9_-]+)"#, #"[?&]id=([A-Za-z0-9_-]+)"#, #"^([A-Za-z0-9_-]{10,})$"#]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) { return String(text[range]) }
        }
        return nil
    }

    private func patterns() -> [String] {
        var p: [String] = []
        if selectedTypes.contains("PDF") { p += ["*.[pP][dD][fF]"] }
        if selectedTypes.contains("EXE") { p += ["*.[eE][xX][eE]"] }
        if selectedTypes.contains("Ebooks") { p += ["*.epub", "*.EPUB", "*.mobi", "*.MOBI", "*.azw", "*.AZW", "*.azw3", "*.AZW3"] }
        if selectedTypes.contains("Documentos") { p += ["*.doc", "*.DOC", "*.docx", "*.DOCX", "*.txt", "*.TXT", "*.rtf", "*.RTF"] }
        if selectedTypes.contains("Comprimidos") { p += ["*.zip", "*.ZIP", "*.rar", "*.RAR", "*.7z"] }
        if selectedTypes.contains("Imágenes") { p += ["*.jpg", "*.JPG", "*.jpeg", "*.JPEG", "*.png", "*.PNG", "*.gif", "*.GIF"] }
        if selectedTypes.contains("Videos") { p += ["*.mp4", "*.MP4", "*.mov", "*.MOV", "*.mkv", "*.MKV", "*.avi", "*.AVI"] }
        if selectedTypes.contains("Audio") { p += ["*.mp3", "*.MP3", "*.wav", "*.WAV", "*.m4a", "*.M4A", "*.flac", "*.FLAC"] }
        return p
    }
}

struct ContentView: View {
    @StateObject private var model = DriveDownloader()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "icloud.and.arrow.down.fill").font(.system(size: 34)).foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Descargador Masivo Google Drive").font(.title2.bold())
                    Text("Pega una carpeta, elige los formatos y descarga todo.").foregroundStyle(.secondary)
                }
            }

            GroupBox("1. Google Drive") {
                HStack {
                    Picker("Conexión", selection: $model.selectedRemote) {
                        Text("Sin conectar").tag("")
                        ForEach(model.remotes, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Actualizar") { model.loadSharedDrives() }.disabled(model.isRunning || model.selectedRemote.isEmpty)
                    Button("Conectar Google Drive") { model.connectGoogle() }.disabled(model.isRunning)
                }.padding(6)
                HStack {
                    Text("Unidad compartida")
                    Picker("", selection: $model.selectedSharedDriveID) {
                        Text("Selecciona una unidad").tag("")
                        ForEach(model.sharedDrives) { drive in Text(drive.name).tag(drive.id) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }.padding([.horizontal, .bottom], 6)
                Toggle("Recorrer automáticamente todas las unidades compartidas", isOn: $model.allSharedDrives)
                    .padding([.horizontal, .bottom], 6)
            }

            GroupBox("2. Enlace de la carpeta") {
                TextField("https://drive.google.com/drive/folders/…", text: $model.driveURL)
                    .textFieldStyle(.roundedBorder).padding(6)
            }

            GroupBox("3. Carpeta de destino") {
                HStack {
                    Text(model.destination.isEmpty ? "Ninguna carpeta seleccionada" : model.destination)
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Elegir carpeta…") { model.chooseDestination() }
                }.padding(6)
            }

            GroupBox("4. Tipos de archivo") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(model.fileTypes, id: \.self) { type in
                        Toggle(type, isOn: Binding(get: { model.selectedTypes.contains(type) }, set: { _ in model.toggleType(type) }))
                    }
                }.padding(6)
            }

            HStack {
                Button("Detectar PDF") { model.scanPDFs() }
                    .controlSize(.large).disabled(model.isRunning)
                Button(model.isRunning ? "Trabajando…" : "Descargar inteligente") { model.startDownload() }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isRunning)
                if model.isRunning { Button("Detener") { model.stop() }.controlSize(.large) }
                Spacer()
            }

            Text(model.progressSummary)
                .font(.headline)
                .foregroundStyle(.blue)

            ScrollView {
                Text(model.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.frame(minHeight: 125).background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(24).frame(minWidth: 720, minHeight: 650)
        .onAppear { model.refreshRemotes() }
    }
}

@main
struct DriveDownloaderApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .windowStyle(.hiddenTitleBar)
    }
}
