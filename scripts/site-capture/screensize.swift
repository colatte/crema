// Prints the main display's size in points, width then height: the capture
// script's regions are taken from it.
import AppKit

if let frame = NSScreen.screens.first?.frame {
    print(Int(frame.width), Int(frame.height))
} else {
    exit(1)
}
