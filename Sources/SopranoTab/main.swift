import AppKit

// Sub-commands run before the app launches and never return: the snapshot harness and the
// CLI (`list`, `focus`, `show`, `hide`, `help`).
let launchArguments = CommandLine.arguments
if launchArguments.count > 1 {
    let command = launchArguments[1]
    if command == "snapshot" {
        SnapshotCommand.run(arguments: Array(launchArguments.dropFirst(2)))
    }
    if CLIClient.commands.contains(command) {
        CLIClient.run(arguments: Array(launchArguments.dropFirst()))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
