import AppKit

// Draws Resources/AppIcon.svg onto a 1024 x 1024 canvas the way macOS app icons are laid out (the shape about 824 points high,
// centred, with room around it) and writes the PNG given as the second argument.
let args = CommandLine.arguments
guard args.count == 3, let image = NSImage(contentsOfFile: args[1]) else { print("cannot read the SVG"); exit(1) }
let canvas = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.clear.set()
NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
let box: CGFloat = 824
let aspect = image.size.width / image.size.height
let h = box, w = box * aspect
let rect = NSRect(x: (CGFloat(canvas) - w) / 2, y: (CGFloat(canvas) - h) / 2, width: w, height: h)
// A soft shadow under the shape, as system icons have.
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 18
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]) from an image of \(image.size)")
