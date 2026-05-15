# Tippi macOS Menu Bar Icon - Black / White

Files:
- tippi-menubar-black.png: 18x18 px, black on transparent
- tippi-menubar-black@2x.png: 36x36 px, black on transparent
- tippi-menubar-white.png: 18x18 px, white on transparent
- tippi-menubar-white@2x.png: 36x36 px, white on transparent

Recommended macOS implementation:
Use the black PNG as a Template Image and set:

let image = NSImage(named: "tippi-menubar-black")
image?.isTemplate = true

macOS will automatically tint it for Light Mode, Dark Mode and menu bar states.
