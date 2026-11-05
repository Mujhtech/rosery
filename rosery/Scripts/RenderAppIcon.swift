import AppKit

// Rebuild with: swift Scripts/RenderAppIcon.swift <output.png>
let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

context.setFillColor(color(0xF7F7F2))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
let light = CGGradient(colorsSpace: space, colors: [color(0xFAFAF6), color(0xF7F7F2)] as CFArray,
                       locations: [0, 1])!
context.drawRadialGradient(light, startCenter: CGPoint(x: 150, y: 950), startRadius: 0,
                           endCenter: CGPoint(x: 150, y: 950), endRadius: 950, options: .drawsAfterEndLocation)

let samples = (0...1440).map { index in
    let angle = Double(index) / 1440 * .pi * 2
    return CGPoint(x: sin(angle), y: cos(angle) * 0.77)
}
var lengths = [0.0]
for index in 1..<samples.count {
    lengths.append(lengths[index - 1] + hypot(samples[index].x - samples[index - 1].x,
                                             samples[index].y - samples[index - 1].y))
}
let total = lengths.last!
let angle = 22.0 * .pi / 180
func point(_ point: CGPoint) -> CGPoint {
    CGPoint(x: 512 + (point.x * cos(angle) - point.y * sin(angle)) * 345,
            y: 512 + (point.x * sin(angle) + point.y * cos(angle)) * 345)
}

let thread = CGMutablePath()
for (index, sample) in samples.enumerated() {
    if index == 0 { thread.move(to: point(sample)) }
    else { thread.addLine(to: point(sample)) }
}
context.addPath(thread)
context.setStrokeColor(color(0x978262, alpha: 0.6))
context.setLineWidth(3)
context.strokePath()

for index in 0..<33 {
    let sample = lengths.firstIndex { $0 >= Double(index) / 33 * total } ?? 0
    let center = point(samples[sample])
    let pearl = index == 0
    let radius: CGFloat = pearl ? 31 : 28
    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 7, height: -12), blur: 15, color: color(0x202322, alpha: 0.65))
    context.setFillColor(color(pearl ? 0xB8A37E : 0x252727))
    context.fillEllipse(in: rect)
    context.restoreGState()
    context.saveGState()
    context.addEllipse(in: rect)
    context.clip()
    let palette: [CGColor] = pearl
        ? [color(0xEEE4CC), color(0xC9B88F), color(0x9F8860), color(0x5B4C35)]
        : [color(0x8C9291), color(0x4A4F4E), color(0x252929), color(0x131515)]
    let gradient = CGGradient(colorsSpace: space, colors: palette as CFArray, locations: [0, 0.28, 0.65, 1])!
    let highlight = CGPoint(x: center.x - radius * 0.4, y: center.y + radius * 0.4)
    context.drawRadialGradient(gradient, startCenter: highlight, startRadius: 0,
                               endCenter: highlight, endRadius: radius * 1.9, options: .drawsAfterEndLocation)
    context.setFillColor(color(0xFFFFFF, alpha: pearl ? 0.5 : 0.2))
    context.fillEllipse(in: CGRect(x: center.x - radius * 0.55, y: center.y + radius * 0.3,
                                  width: radius * 0.65, height: radius * 0.23))
    context.restoreGState()
}

let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("Rendered 1024 × 1024 opaque Rosery icon.")
