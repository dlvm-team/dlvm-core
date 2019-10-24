//
//  Error.swift
//  DLCommandLineTools
//
//  Copyright 2016-2018 The DLVM Team.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Basic
import SPMUtility

public enum DLError: Error {
    /// No input files were specified.
    case noInputFiles
    /// An input file is invalid.
    // NOTE: To be removed when PathArgument init checks for invalid paths.
    case invalidInputFile(AbsolutePath)
    /// The number of input files and output paths do not match.
    case inputOutputCountMismatch
    /// There were fatal diagnostics during the operation.
    case hasFatalDiagnostics
}

extension DLError : CustomStringConvertible {
    public var description: String {
        switch self {
        case .noInputFiles:
            return "no input files"
        case .invalidInputFile(let path):
            return "invalid input path: \(path.prettyPath())"
        case .inputOutputCountMismatch:
            return "number of inputs and outputs do not match"
        case .hasFatalDiagnostics:
            return ""
        }
    }
}

public func printError(_ error: Any) {
    let writer = InteractiveWriter.stderr
    writer.write("error: ", in: .red, bold: true)
    writer.write("\(error)")
    writer.write("\n")
}

func printDiagnostic(_ diagnostic: Diagnostic) {
    let writer = InteractiveWriter.stderr
    if !(diagnostic.location is UnknownLocation) {
        writer.write(diagnostic.location.localizedDescription)
        writer.write(": ")
    }
    switch diagnostic.behavior {
    case .error:
        writer.write("error: ", in: .red, bold: true)
    case .warning:
        writer.write("warning: ", in: .yellow, bold: true)
    case .note:
        writer.write("note: ", in: .white, bold: true)
    case .ignored:
        return
    }
    writer.write(diagnostic.localizedDescription)
    writer.write("\n")
}

func printDiagnostic(_ data: DiagnosticData) {
    printDiagnostic(Diagnostic(
        location: UnknownLocation.location,
        data: data
    ))
}

internal func handleError(_ error: Any) {
    switch error {
    case ArgumentParserError.expectedArguments(let parser, _):
        printError(error)
        parser.printUsage(on: stderrStream)
    default:
        printError(error)
    }
}

/// This class is used to write on the underlying stream.
///
/// If underlying stream is a not tty, the string will be written in without any
/// formatting.
private final class InteractiveWriter {
    /// The standard error writer.
    static let stderr = InteractiveWriter(stream: stderrStream)

    /// The terminal controller, if present.
    let term: TerminalController?

    /// The output byte stream reference.
    let stream: OutputByteStream

    /// Create an instance with the given stream.
    init(stream: OutputByteStream) {
        self.term = (stream as? LocalFileOutputByteStream)
            .flatMap(TerminalController.init(stream:))
        self.stream = stream
    }

    /// Write the string to the contained terminal or stream.
    func write(_ string: String,
               in color: TerminalController.Color = .noColor,
               bold: Bool = false) {
        if let term = term {
            term.write(string, inColor: color, bold: bold)
        } else {
            stream <<< string
            stream.flush()
        }
    }
}
