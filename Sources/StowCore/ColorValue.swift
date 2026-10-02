import Foundation

struct ColorValue: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var hex: String {
        func channel(_ value: Double) -> String {
            String(format: "%02X", Int((min(1, max(0, value)) * 255).rounded()))
        }
        let rgb = "#" + channel(red) + channel(green) + channel(blue)
        if alpha >= 0.999 {
            return rgb
        }
        return rgb + channel(alpha)
    }

    func rgbString() -> String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        if alpha >= 0.999 {
            return "rgb(\(r), \(g), \(b))"
        }
        return String(format: "rgba(%d, %d, %d, %.2f)", r, g, b, alpha)
    }

    func hslString() -> String {
        let (h, s, l) = hsl
        if alpha >= 0.999 {
            return String(format: "hsl(%.0f, %.0f%%, %.0f%%)", h, s * 100, l * 100)
        }
        return String(format: "hsla(%.0f, %.0f%%, %.0f%%, %.2f)", h, s * 100, l * 100, alpha)
    }

    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maxChannel = max(red, green, blue)
        let minChannel = min(red, green, blue)
        let lightness = (maxChannel + minChannel) / 2
        let delta = maxChannel - minChannel
        guard delta > 0.00001 else {
            return (0, 0, lightness)
        }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        let hue: Double
        if maxChannel == red {
            hue = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxChannel == green {
            hue = 60 * (((blue - red) / delta) + 2)
        } else {
            hue = 60 * (((red - green) / delta) + 4)
        }
        return (hue < 0 ? hue + 360 : hue, saturation, lightness)
    }

    static func parse(_ raw: String) -> ColorValue? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            return parseHex(String(text.dropFirst()))
        }
        let lower = text.lowercased()
        if lower.hasPrefix("rgba") || lower.hasPrefix("rgb") {
            return parseRGB(lower)
        }
        if lower.hasPrefix("hsla") || lower.hasPrefix("hsl") {
            return parseHSL(lower)
        }
        return nil
    }

    private static func parseHex(_ body: String) -> ColorValue? {
        let hex = body.trimmingCharacters(in: .whitespaces)
        guard hex.allSatisfy(\.isHexDigit) else { return nil }
        func channel(_ pair: Substring) -> Double? {
            guard let value = Int(pair, radix: 16) else { return nil }
            return Double(value) / 255
        }
        switch hex.count {
        case 3, 4:
            let expanded = hex.map { String(repeating: String($0), count: 2) }.joined()
            return parseHex(expanded)
        case 6, 8:
            func pair(_ start: Int) -> Double? {
                let startIndex = hex.index(hex.startIndex, offsetBy: start)
                let endIndex = hex.index(startIndex, offsetBy: 2)
                return channel(hex[startIndex..<endIndex])
            }
            guard let red = pair(0), let green = pair(2), let blue = pair(4) else { return nil }
            let alpha = hex.count == 8 ? pair(6) : 1
            guard let alpha else { return nil }
            return ColorValue(red: red, green: green, blue: blue, alpha: alpha)
        default:
            return nil
        }
    }

    private static func parseRGB(_ text: String) -> ColorValue? {
        let numbers = components(in: text)
        guard numbers.count == 3 || numbers.count == 4 else { return nil }
        func rgbChannel(_ token: String) -> Double? {
            if token.hasSuffix("%") {
                guard let value = Double(token.dropLast()) else { return nil }
                return min(1, max(0, value / 100))
            }
            guard let value = Double(token) else { return nil }
            return min(1, max(0, value / 255))
        }
        guard let red = rgbChannel(numbers[0]),
              let green = rgbChannel(numbers[1]),
              let blue = rgbChannel(numbers[2]) else { return nil }
        let alpha = numbers.count == 4 ? alphaChannel(numbers[3]) : 1
        guard let alpha else { return nil }
        return ColorValue(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func parseHSL(_ text: String) -> ColorValue? {
        let numbers = components(in: text)
        guard numbers.count == 3 || numbers.count == 4 else { return nil }
        guard let hue = Double(numbers[0].replacingOccurrences(of: "deg", with: "")) else { return nil }
        func percent(_ token: String) -> Double? {
            let cleaned = token.hasSuffix("%") ? String(token.dropLast()) : token
            guard let value = Double(cleaned) else { return nil }
            return min(1, max(0, value / 100))
        }
        guard let saturation = percent(numbers[1]), let lightness = percent(numbers[2]) else { return nil }
        let alpha = numbers.count == 4 ? alphaChannel(numbers[3]) : 1
        guard let alpha else { return nil }
        return fromHSL(hue: hue, saturation: saturation, lightness: lightness, alpha: alpha)
    }

    private static func alphaChannel(_ token: String) -> Double? {
        if token.hasSuffix("%") {
            guard let value = Double(token.dropLast()) else { return nil }
            return min(1, max(0, value / 100))
        }
        guard let value = Double(token) else { return nil }
        if value > 1 {
            return min(1, value / 255)
        }
        return min(1, max(0, value))
    }

    private static func components(in text: String) -> [String] {
        guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")") else { return [] }
        let body = text[text.index(after: open)..<close]
        return body
            .split { $0 == "," || $0 == "/" || $0.isWhitespace }
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    private static func fromHSL(hue: Double, saturation: Double, lightness: Double, alpha: Double) -> ColorValue {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        func hueToRGB(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        if saturation == 0 {
            return ColorValue(red: lightness, green: lightness, blue: lightness, alpha: alpha)
        }
        let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        return ColorValue(
            red: hueToRGB(p, q, h + 1 / 3),
            green: hueToRGB(p, q, h),
            blue: hueToRGB(p, q, h - 1 / 3),
            alpha: alpha
        )
    }
}
