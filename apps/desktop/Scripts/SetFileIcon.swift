// Gives a file a custom Finder icon — run by make-dmg.sh so Vitals.dmg shows the
// app icon in Downloads/Finder instead of the generic disk-image icon.
// The icon lives in the file's resource fork (an extended attribute), so it
// doesn't change the signed disk-image data.
//   swift Scripts/SetFileIcon.swift <file> <icon.icns|png>
import Cocoa

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: SetFileIcon <file> <icon>\n".utf8))
    exit(2)
}
let target = CommandLine.arguments[1]
let iconPath = CommandLine.arguments[2]

guard let icon = NSImage(contentsOfFile: iconPath) else {
    FileHandle.standardError.write(Data("could not load icon: \(iconPath)\n".utf8))
    exit(1)
}

if NSWorkspace.shared.setIcon(icon, forFile: target, options: []) {
    print("set custom icon on \(target)")
} else {
    FileHandle.standardError.write(Data("failed to set icon on \(target)\n".utf8))
    exit(1)
}
