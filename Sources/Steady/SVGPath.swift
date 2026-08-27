import CoreGraphics
import SwiftUI

struct SVGShape: Shape {
    private let base: CGPath
    init(_ d: String) { base = SVGParser.cgPath(d) }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * scale) / 2
        let dy = (rect.height - 24 * scale) / 2
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: dx, y: dy))
        return Path(base).applying(transform)
    }
}

private final class SVGScanner {
    private let chars: [Character]
    private var index = 0
    init(_ string: String) { chars = Array(string) }

    private func skipSeparators() {
        while index < chars.count {
            let c = chars[index]
            if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" { index += 1 } else { break }
        }
    }

    func command() -> Character? {
        skipSeparators()
        guard index < chars.count, chars[index].isLetter else { return nil }
        let c = chars[index]
        index += 1
        return c
    }

    var hasNumber: Bool {
        var j = index
        while j < chars.count {
            let c = chars[j]
            if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" { j += 1 } else { break }
        }
        guard j < chars.count else { return false }
        let c = chars[j]
        return c.isNumber || c == "-" || c == "+" || c == "."
    }

    func number() -> CGFloat {
        skipSeparators()
        var str = ""
        if index < chars.count, chars[index] == "-" || chars[index] == "+" { str.append(chars[index]); index += 1 }
        var dotSeen = false
        while index < chars.count {
            let c = chars[index]
            if c.isNumber { str.append(c); index += 1 }
            else if c == "." && !dotSeen { dotSeen = true; str.append(c); index += 1 }
            else if c == "e" || c == "E" {
                str.append(c); index += 1
                if index < chars.count, chars[index] == "-" || chars[index] == "+" { str.append(chars[index]); index += 1 }
            } else { break }
        }
        return CGFloat(Double(str) ?? 0)
    }

    func point(relative: Bool, to current: CGPoint) -> CGPoint {
        let x = number(), y = number()
        return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }
}

private enum SVGParser {
    static func cgPath(_ d: String) -> CGPath {
        let path = CGMutablePath()
        let scanner = SVGScanner(d)
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var prevControl: CGPoint?
        var prevCommand: Character = " "

        while let command = scanner.command() {
            let relative = command.isLowercase
            switch Character(command.uppercased()) {
            case "M":
                var p = scanner.point(relative: relative, to: current)
                path.move(to: p); current = p; subpathStart = p
                while scanner.hasNumber {
                    p = scanner.point(relative: relative, to: current)
                    path.addLine(to: p); current = p
                }
                prevControl = nil
            case "L":
                while scanner.hasNumber {
                    let p = scanner.point(relative: relative, to: current)
                    path.addLine(to: p); current = p
                }
                prevControl = nil
            case "H":
                while scanner.hasNumber {
                    let x = scanner.number() + (relative ? current.x : 0)
                    current = CGPoint(x: x, y: current.y); path.addLine(to: current)
                }
                prevControl = nil
            case "V":
                while scanner.hasNumber {
                    let y = scanner.number() + (relative ? current.y : 0)
                    current = CGPoint(x: current.x, y: y); path.addLine(to: current)
                }
                prevControl = nil
            case "C":
                while scanner.hasNumber {
                    let c1 = scanner.point(relative: relative, to: current)
                    let c2 = scanner.point(relative: relative, to: current)
                    let end = scanner.point(relative: relative, to: current)
                    path.addCurve(to: end, control1: c1, control2: c2)
                    prevControl = c2; current = end
                }
            case "S":
                while scanner.hasNumber {
                    let reflect = "CS".contains(Character(prevCommand.uppercased())) && prevControl != nil
                    let c1 = reflect ? CGPoint(x: 2 * current.x - prevControl!.x, y: 2 * current.y - prevControl!.y) : current
                    let c2 = scanner.point(relative: relative, to: current)
                    let end = scanner.point(relative: relative, to: current)
                    path.addCurve(to: end, control1: c1, control2: c2)
                    prevControl = c2; current = end
                }
            case "Q":
                while scanner.hasNumber {
                    let c = scanner.point(relative: relative, to: current)
                    let end = scanner.point(relative: relative, to: current)
                    path.addQuadCurve(to: end, control: c)
                    prevControl = c; current = end
                }
            case "T":
                while scanner.hasNumber {
                    let reflect = "QT".contains(Character(prevCommand.uppercased())) && prevControl != nil
                    let c = reflect ? CGPoint(x: 2 * current.x - prevControl!.x, y: 2 * current.y - prevControl!.y) : current
                    let end = scanner.point(relative: relative, to: current)
                    path.addQuadCurve(to: end, control: c)
                    prevControl = c; current = end
                }
            case "A":
                while scanner.hasNumber {
                    let rx = scanner.number(), ry = scanner.number()
                    let rotation = scanner.number()
                    let largeArc = scanner.number() != 0
                    let sweep = scanner.number() != 0
                    let end = scanner.point(relative: relative, to: current)
                    addArc(path, from: current, to: end, rx: rx, ry: ry, rotationDegrees: rotation, largeArc: largeArc, sweep: sweep)
                    current = end
                }
                prevControl = nil
            case "Z":
                path.closeSubpath(); current = subpathStart; prevControl = nil
            default:
                break
            }
            prevCommand = command
        }
        return path
    }

    private static func addArc(_ path: CGMutablePath, from p0: CGPoint, to p1: CGPoint,
                               rx rx0: CGFloat, ry ry0: CGFloat, rotationDegrees: CGFloat,
                               largeArc: Bool, sweep: Bool) {
        if p0 == p1 { return }
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }

        let phi = rotationDegrees * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosP * dx + sinP * dy
        let y1p = -sinP * dx + cosP * dy

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = sqrt(lambda); rx *= s; ry *= s }

        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        var numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        if numerator < 0 { numerator = 0 }
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
        let cxp = coefficient * (rx * y1p / ry)
        let cyp = coefficient * (-ry * x1p / rx)
        let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(max(-1, min(1, len == 0 ? 1 : dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry
        let theta1 = angle(1, 0, ux, uy)
        var delta = angle(ux, uy, vx, vy)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        var transform = CGAffineTransform(translationX: cx, y: cy)
        transform = transform.rotated(by: phi)
        transform = transform.scaledBy(x: rx, y: ry)
        path.addArc(center: .zero, radius: 1, startAngle: theta1, endAngle: theta1 + delta,
                    clockwise: delta < 0, transform: transform)
    }
}
