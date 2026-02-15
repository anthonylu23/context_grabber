import Foundation

@main
enum ContextGrabberHostLauncher {
  static func main() async {
    let arguments = CommandLine.arguments
    if CLIEntryPoint.isCaptureInvocation(arguments: arguments) {
      exit(await CLIEntryPoint.run(arguments: arguments))
    }

    ContextGrabberHostApp.main()
  }
}
