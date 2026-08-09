import AppKit

// Explicit entry point rather than @main on the App: the binary has to decide, before AppKit starts,
// whether this invocation is a terminal command or the GUI. Once NSApplication is running it is too
// late to exit cleanly with a status code.
let arguments = Array(CommandLine.arguments.dropFirst())
if CommandLineMode.shouldHandle(arguments) {
    CommandLineMode.run(arguments)
}
LinkRouterApp.main()
