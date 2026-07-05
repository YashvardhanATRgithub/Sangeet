#!/usr/bin/env swift
//
// Renders the DMG installer background (660x400):
// dark gradient, app title, and a drag arrow between the two icon positions.
// Usage: swift generate_dmg_background.swift <output.png>
//

import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg_background.png"

let width = 660.0
let height = 400.0
let size = NSSize(width: width, height: height)

let image = NSImage(size: size)
image.lockFocus()

// Background: deep dark gradient with a purple tint (matches app theme)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.07, green: 0.06, blue: 0.10, alpha: 1.0),
    NSColor(calibratedRed: 0.12, green: 0.09, blue: 0.18, alpha: 1.0)
])!
gradient.draw(in: NSRect(origin: .zero, size: size), angle: 100)

// Subtle glow behind the center
let glow = NSGradient(colors: [
    NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.95, alpha: 0.16),
    NSColor.clear
])!
glow.draw(fromCenter: NSPoint(x: width / 2, y: 200), radius: 0,
          toCenter: NSPoint(x: width / 2, y: 200), radius: 320, options: [])

let accent = NSColor(calibratedRed: 0.62, green: 0.42, blue: 0.96, alpha: 1.0)

// Title
let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center
("Sangeet" as NSString).draw(
    in: NSRect(x: 0, y: height - 88, width: width, height: 48),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 34, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: titleStyle
    ]
)

// Subtitle
("Drag Sangeet to the Applications folder to install" as NSString).draw(
    in: NSRect(x: 0, y: height - 118, width: width, height: 22),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 14, weight: .medium),
        .foregroundColor: NSColor(white: 1.0, alpha: 0.55),
        .paragraphStyle: titleStyle
    ]
)

// Drag arrow between icon positions (icons sit at x=165 and x=495, y-center 200 from bottom)
let arrowY = 200.0
let arrowStart = 255.0
let arrowEnd = 400.0

let line = NSBezierPath()
line.move(to: NSPoint(x: arrowStart, y: arrowY))
line.line(to: NSPoint(x: arrowEnd, y: arrowY))
line.lineWidth = 5
line.lineCapStyle = .round
accent.setStroke()
line.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: arrowEnd + 18, y: arrowY))
head.line(to: NSPoint(x: arrowEnd - 4, y: arrowY + 13))
head.line(to: NSPoint(x: arrowEnd - 4, y: arrowY - 13))
head.close()
accent.setFill()
head.fill()

// Footer hint
("Then launch it from Applications or Spotlight" as NSString).draw(
    in: NSRect(x: 0, y: 40, width: width, height: 18),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor(white: 1.0, alpha: 0.35),
        .paragraphStyle: titleStyle
    ]
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to render background\n", stderr)
    exit(1)
}

try! png.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
