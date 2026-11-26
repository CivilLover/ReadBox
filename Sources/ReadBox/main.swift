import Foundation
import SwiftUI

if CommandLine.arguments.contains("--mcp") {
    ReadBoxMCPStdioServer.runFromCommandLine()
    exit(0)
} else {
    ReadBoxApp.main()
}
