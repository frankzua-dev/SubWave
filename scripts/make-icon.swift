// Builds Resources/AppIcon.icns from the artwork in Resources/icon-source.png:
// crops the rounded-square artwork off its white background, masks the
// corners, and places it on Apple's 824-of-1024 icon grid with a soft shadow.
//
//   swift scripts/make-icon.swift
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("Resources/icon-source.png")
let space = CGColorSpace(name: CGColorSpace.sRGB)!

// Artwork bounds and corner radius in the 1254px source image
let artwork = CGRect(x: 114, y: 114, width: 1025, height: 1013)
let artworkCornerRadius: CGFloat = 225
let maskInset: CGFloat = 4 // stay just inside the edge so no white fringe shows

guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
      let full = CGImageSourceCreateImageAtIndex(input, 0, nil),
      let cropped = full.cropping(to: artwork) else {
  fatalError("Couldn't read \(source.path)")
}

func render (size: Int) -> CGImage {
  let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let scale = CGFloat(size) / 1024
  ctx.scaleBy(x: scale, y: scale)
  ctx.interpolationQuality = .high

  let body = CGRect(x: 100, y: 100, width: 824, height: 824).insetBy(dx: maskInset, dy: maskInset)
  let radius = artworkCornerRadius * 824 / artwork.width
  let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
  ctx.addPath(shape)
  ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
  ctx.fillPath()
  ctx.restoreGState()

  ctx.addPath(shape)
  ctx.clip()
  ctx.draw(cropped, in: CGRect(x: 100, y: 100, width: 824, height: 824))
  return ctx.makeImage()!
}

func writePNG (_ image: CGImage, to url: URL) {
  let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, image, nil)
  precondition(CGImageDestinationFinalize(dest))
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("SubWave-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                     ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
  writePNG(render(size: size), to: iconset.appendingPathComponent("icon_\(name).png"))
}
writePNG(render(size: 1024), to: root.appendingPathComponent("Resources/icon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", root.appendingPathComponent("Resources/AppIcon.icns").path, iconset.path]
try! iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")
try? FileManager.default.removeItem(at: iconset)
print("Wrote Resources/AppIcon.icns and Resources/icon-1024.png")
