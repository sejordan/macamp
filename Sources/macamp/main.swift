import Foundation
import MacampCore

if let status = CLI.run(Array(CommandLine.arguments.dropFirst())) {
    exit(status)
}
print(CLI.usage)
