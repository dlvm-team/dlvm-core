//
//  Tool.swift
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

#if os(Linux)
@_exported import Glibc
#else
@_exported import Darwin.C
#endif

import Basic
import SPMUtility
import struct DLVM.OrderedSet

open class CommandLineTool<Options : ToolOptions> {
    /// An enum indicating the execution status of run commands.
    enum ExecutionStatus {
        case success
        case failure
    }

    /// The options of this tool.
    public let options: Options

    /// Reference to the argument parser.
    public let parser: ArgumentParser

    /// The execution status of the tool.
    var executionStatus: ExecutionStatus = .success

    /// Create an instance of this tool.
    ///
    /// - parameter args: The command line arguments to be passed to this tool.
    public init(name: String, usage: String, overview: String,
                arguments: [String], seeAlso: String? = nil) {
        // Create the parser.
        parser = ArgumentParser(
            commandName: name,
            usage: usage,
            overview: overview,
            seeAlso: seeAlso
        )

        // Create the binder.
        let binder = ArgumentBinder<Options>()

        // Bind the common options.
        binder.bindArray(
            positional: parser.add(positional: "input files",
                                   kind: [PathArgument].self,
                                   usage: "DLVM IR input files"),
            to: { $0.inputFiles = $1.lazy.map({ $0.path }) }
        )

        binder.bindArray(
            parser.add(option: "--passes", shortName: "-p",
                       kind: [TransformPass].self,
                       usage: "Transform passes"),
            parser.add(option: "--outputs", shortName: "-o",
                       kind: [PathArgument].self,
                       usage: "Output paths"),
            to: {
                if !$1.isEmpty { $0.passes = DLVM.OrderedSet($1) }
                if !$2.isEmpty { $0.outputPaths = $2.lazy.map({ $0.path }) }
            }
        )

        binder.bind(
            option: parser.add(option: "--print-ir", kind: Bool.self,
                               usage: """
                                   Print IR after transformations instead of \
                                   writing to files
                                   """),
            to: { $0.shouldPrintIR = $1 }
        )

        // Let subclasses bind arguments.
        type(of: self).setUp(parser: parser, binder: binder)

        do {
            // Parse the result.
            let result = try parser.parse(arguments)
            // Fill and set options.
            var options = Options()
            try! binder.fill(parseResult: result, into: &options)
            // Validate options.
            if let passes = options.passes, passes.contains(.differentiation) {
                printDiagnostic(RedundantDifferentiationFlagDiagnostic())
                options.passes?.remove(.differentiation)
            }
            self.options = options
        } catch {
            handleError(error)
            CommandLineTool.exit(with: .failure)
        }
    }

    open class func setUp(parser: ArgumentParser,
                          binder: ArgumentBinder<Options>) {
        fatalError("Must be implemented by subclasses")
    }

    /// Run method implementation to be overridden by subclasses.
    open func run() throws {
        fatalError("Must be implemented by subclasses")
    }

    /// Exit the tool with the given execution status.
    static func exit(with status: ExecutionStatus) -> Never {
        switch status {
            #if os(Linux)
        case .success: Glibc.exit(EXIT_SUCCESS)
        case .failure: Glibc.exit(EXIT_FAILURE)
            #else
        case .success: Darwin.exit(EXIT_SUCCESS)
        case .failure: Darwin.exit(EXIT_FAILURE)
            #endif
        }
    }
}

public extension CommandLineTool {
    /// Execute the tool.
    final func runAndDiagnose() {
        do {
            // Call the implementation.
            try run()
        } catch {
            // Set execution status to failure in case of errors.
            executionStatus = .failure
            handleError(error)
        }
        CommandLineTool.exit(with: executionStatus)
    }
}
