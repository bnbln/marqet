// App Store screenshots: captures the demo app in the simulator and frames the captures as posters.
// Built and run by scripts/screenshots/make.sh – see there for usage. Config: shots.json.
//
//   capture: per device × language × shot, launch the app with `-demo <shot args>`, wait, screenshot
//            → screenshots/raw/<lang>/<device>/<shot>.png
//   frame:   headline + subline above the device (Apple bezel from bezels/, else a drawn frame)
//            → screenshots/final/<lang>/<device>/<shot>.png, opaque sRGB PNG in App Store size

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Config

struct Config: Decodable {
    struct Style: Decodable { let background, title, subtitle, frame: String }
    struct Language: Decodable { let code, locale: String }
    struct Device: Decodable {
        let id, simulator: String
        /// Output size in pixels; `nil` keeps the capture's own size.
        let canvas: [Int]?
        let bezel: String?
        /// Headline size as a fraction of the canvas' shorter side.
        let titleSize: Double
        /// Screen corner radius as a fraction of the screen's shorter side (drawn frame only).
        let screenCorner: Double
        /// Asked before capturing, for poses the tool can't set (iPhone Duo folded/open).
        let prompt: String?
        /// Screen to capture (`simctl io screenshot --display`); iPhone Duo: 1 outer, 3 inner.
        let display: String?
    }
    struct Shot: Decodable {
        let id: String
        let args: [String]
        let wait: Double
        let devices: [String]?
        let title, subtitle: [String: String]
    }

    let bundleID, app: String
    let location: [Double]
    let style: Style
    let languages: [Language]
    let devices: [Device]
    let shots: [Shot]
}

let toolDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let root = toolDir.deletingLastPathComponent().deletingLastPathComponent()
let rawDir = root.appending(path: "screenshots/raw")
let finalDir = root.appending(path: "screenshots/final")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✘ \(message)\n".utf8))
    exit(1)
}

func log(_ message: String) { print(message) }

// MARK: - Arguments

var mode = "all"
var filters: [String: Set<String>] = [:]
var arguments = Array(CommandLine.arguments.dropFirst())
if let first = arguments.first, !first.hasPrefix("--") { mode = arguments.removeFirst() }
while !arguments.isEmpty {
    let flag = arguments.removeFirst()
    guard flag.hasPrefix("--"), !arguments.isEmpty else { fail("Unbekanntes Argument \(flag)") }
    filters[String(flag.dropFirst(2)), default: []].formUnion(arguments.removeFirst().split(separator: ",").map(String.init))
}
guard ["all", "capture", "frame"].contains(mode) else { fail("Modus: all | capture | frame") }

func included(_ value: String, _ key: String) -> Bool { filters[key].map { $0.contains(value) } ?? true }

let config: Config
do {
    config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: toolDir.appending(path: "shots.json")))
} catch {
    fail("shots.json: \(error)")
}
let devices = config.devices.filter { included($0.id, "devices") }
let languages = config.languages.filter { included($0.code, "langs") }
let shots = config.shots.filter { included($0.id, "shots") }

// MARK: - Capture

@discardableResult
func xcrun(_ args: [String], allowFailure: Bool = false) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = allowFailure ? FileHandle.nullDevice : FileHandle.standardError
    do { try process.run() } catch { fail("xcrun: \(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if process.terminationStatus != 0, !allowFailure { fail("xcrun \(args.joined(separator: " ")) ist fehlgeschlagen") }
    return String(decoding: data, as: UTF8.self)
}

/// The simulator with that name – a booted one first, else the newest runtime.
func simulatorID(named name: String) -> String {
    struct List: Decodable {
        struct Device: Decodable { let name, udid, state: String }
        let devices: [String: [Device]]
    }
    let json = xcrun(["simctl", "list", "devices", "available", "-j"])
    guard let list = try? JSONDecoder().decode(List.self, from: Data(json.utf8)) else { fail("simctl list nicht lesbar") }
    let matches = list.devices.sorted { $0.key < $1.key }.flatMap(\.value).filter { $0.name == name }
    guard let device = matches.first(where: { $0.state == "Booted" }) ?? matches.last else {
        fail("Kein Simulator „\(name)“ – in shots.json anpassen oder in Xcode anlegen")
    }
    return device.udid
}

func prepare(_ udid: String) {
    xcrun(["simctl", "boot", udid], allowFailure: true)
    xcrun(["simctl", "bootstatus", udid, "-b"])
    xcrun(["simctl", "ui", udid, "appearance", "light"])
    xcrun(["simctl", "status_bar", udid, "override", "--time", "9:41",
           "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
           "--cellularMode", "active", "--cellularBars", "4",
           "--batteryState", "discharging", "--batteryLevel", "100"])
    xcrun(["simctl", "install", udid, root.appending(path: config.app).path])
    xcrun(["simctl", "privacy", udid, "grant", "location", config.bundleID], allowFailure: true)
    xcrun(["simctl", "location", udid, "set", config.location.map { String($0) }.joined(separator: ",")], allowFailure: true)
}

func capture() {
    guard FileManager.default.fileExists(atPath: root.appending(path: config.app).path) else {
        fail("App fehlt unter \(config.app) – erst bauen (make.sh macht das)")
    }
    for device in devices {
        let udid = simulatorID(named: device.simulator)
        if let prompt = device.prompt {
            log("\n▸ \(prompt)\n  Enter, sobald das Gerät bereit ist …")
            _ = readLine()
        }
        log("▸ \(device.id): \(device.simulator)")
        prepare(udid)
        for language in languages {
            for shot in shots where shot.devices.map({ $0.contains(device.id) }) ?? true {
                let output = rawDir.appending(path: "\(language.code)/\(device.id)/\(shot.id).png")
                try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                xcrun(["simctl", "terminate", udid, config.bundleID], allowFailure: true)
                xcrun(["simctl", "launch", udid, config.bundleID, "-demo", "-screenshots",
                       "-AppleLanguages", "(\(language.code))", "-AppleLocale", language.locale] + shot.args)
                Thread.sleep(forTimeInterval: shot.wait)
                xcrun(["simctl", "io", udid, "screenshot", "--type=png"]
                      + (device.display.map { ["--display=\($0)"] } ?? []) + [output.path])
                log("  ✓ \(language.code)/\(device.id)/\(shot.id)")
            }
        }
        xcrun(["simctl", "terminate", udid, config.bundleID], allowFailure: true)
        xcrun(["simctl", "status_bar", udid, "clear"], allowFailure: true)
    }
}

// MARK: - Frame

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

func loadImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// An Apple device bezel with a transparent screen, found by flood fill from the center –
/// so any bezel PNG works without measuring its screen by hand.
struct Bezel {
    let image: CGImage
    let screen: CGRect

    init?(url: URL) {
        guard let image = loadImage(url) else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func isClear(_ x: Int, _ y: Int) -> Bool { pixels[(y * width + x) * 4 + 3] < 128 }

        let start = (width / 2, height / 2)
        guard isClear(start.0, start.1) else { return nil }
        var visited = [Bool](repeating: false, count: width * height)
        var stack = [start]
        var minX = width, minY = height, maxX = 0, maxY = 0
        while let (x, y) = stack.popLast() {
            guard x >= 0, y >= 0, x < width, y < height, !visited[y * width + x], isClear(x, y) else { continue }
            visited[y * width + x] = true
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        }
        self.image = image
        screen = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

struct DeviceView: View {
    let screenshot: CGImage
    let bezel: Bezel?
    let device: Config.Device
    let frameColor: Color

    var body: some View {
        if let bezel {
            let size = CGSize(width: bezel.image.width, height: bezel.image.height)
            GeometryReader { proxy in
                let scale = proxy.size.width / size.width
                ZStack(alignment: .topLeading) {
                    // 1 px bleed under the bezel, so no background line shows at the screen edge.
                    Image(decorative: screenshot, scale: 1)
                        .resizable()
                        .frame(width: bezel.screen.width * scale + 2, height: bezel.screen.height * scale + 2)
                        .offset(x: bezel.screen.minX * scale - 1, y: bezel.screen.minY * scale - 1)
                    Image(decorative: bezel.image, scale: 1)
                        .resizable()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .aspectRatio(size.width / size.height, contentMode: .fit)
        } else {
            // Drawn frame: a slim dark band around the screen, corners following the display.
            let shot = CGSize(width: screenshot.width, height: screenshot.height)
            let border = min(shot.width, shot.height) * 0.028
            let outer = CGSize(width: shot.width + border * 2, height: shot.height + border * 2)
            GeometryReader { proxy in
                let scale = proxy.size.width / outer.width
                let radius = min(shot.width, shot.height) * device.screenCorner * scale
                Image(decorative: screenshot, scale: 1)
                    .resizable()
                    .clipShape(.rect(cornerRadius: radius, style: .continuous))
                    .padding(border * scale)
                    .background(frameColor, in: .rect(cornerRadius: radius + border * scale, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: proxy.size.width * 0.04, y: proxy.size.width * 0.02)
            }
            .aspectRatio(outer.width / outer.height, contentMode: .fit)
        }
    }
}

struct Poster: View {
    let canvas: CGSize
    let title: String
    let subtitle: String
    let device: DeviceView
    let titleFraction: Double
    let style: Config.Style

    var body: some View {
        let unit = min(canvas.width, canvas.height)
        let titleSize = unit * titleFraction
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: titleSize, weight: .semibold))
                .tracking(-titleSize * 0.015)
                .lineSpacing(titleSize * 0.02)
                .foregroundStyle(Color(hex: style.title))
            Text(subtitle)
                .font(.system(size: titleSize * 0.45, weight: .regular))
                .foregroundStyle(Color(hex: style.subtitle))
                .padding(.top, titleSize * 0.35)
            device
                .padding(.top, titleSize * 0.8)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .multilineTextAlignment(.center)
        .padding(.top, canvas.height * 0.055)
        .padding(.bottom, canvas.height * 0.035)
        .padding(.horizontal, canvas.width * 0.08)
        .frame(width: canvas.width, height: canvas.height)
        .background(Color(hex: style.background))
    }
}

/// App Store Connect rejects screenshots with an alpha channel: flatten into opaque sRGB.
func writeOpaquePNG(_ image: CGImage, to url: URL) {
    guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fail("Kein Grafikkontext") }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let flat = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("PNG nicht schreibbar: \(url.path)") }
    CGImageDestinationAddImage(destination, flat, nil)
    guard CGImageDestinationFinalize(destination) else { fail("PNG nicht schreibbar: \(url.path)") }
}

@MainActor
func frame() {
    var count = 0
    for device in devices {
        let bezel = device.bezel.flatMap { Bezel(url: toolDir.appending(path: $0)) }
        if device.bezel != nil, bezel == nil {
            log("▸ \(device.id): kein Bezel unter \(device.bezel!) – zeichne einen Rahmen")
        }
        for language in languages {
            for shot in shots {
                let input = rawDir.appending(path: "\(language.code)/\(device.id)/\(shot.id).png")
                guard let screenshot = loadImage(input) else { continue }
                let canvas = device.canvas.map { CGSize(width: $0[0], height: $0[1]) }
                    ?? CGSize(width: screenshot.width, height: screenshot.height)
                let poster = Poster(
                    canvas: canvas,
                    title: shot.title[language.code] ?? "",
                    subtitle: shot.subtitle[language.code] ?? "",
                    device: DeviceView(screenshot: screenshot, bezel: bezel, device: device,
                                       frameColor: Color(hex: config.style.frame)),
                    titleFraction: device.titleSize,
                    style: config.style
                )
                let renderer = ImageRenderer(content: poster)
                renderer.scale = 1
                renderer.proposedSize = ProposedViewSize(canvas)
                guard let image = renderer.cgImage else { fail("Rendern fehlgeschlagen: \(shot.id)") }
                let output = finalDir.appending(path: "\(language.code)/\(device.id)/\(shot.id).png")
                try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                writeOpaquePNG(image, to: output)
                count += 1
            }
        }
    }
    log(count == 0 ? "▸ Keine Aufnahmen gefunden – erst „capture“." : "✔ \(count) Werbeshots in screenshots/final")
}

// MARK: - Run

if mode != "frame" { capture() }
if mode != "capture" { MainActor.assumeIsolated { frame() } }
