//
//  main.swift
//  dlopt
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

import DLVM
import DLParse
import DLCommandLineTools
import Foundation
import Basic
import SPMUtility

class OptToolOptions : ToolOptions {
    /// Bypass verification
    var noVerify = false
}

class DLOptTool : CommandLineTool<OptToolOptions> {
    public convenience init(args: [String]) {
        self.init(
            name: "dlopt",
            usage: "<inputs> [options]",
            overview: "DLVM IR optimizer",
            arguments: args
        )
    }

    override func run() throws {
        let outputPaths = options.outputPaths
        if let outputPaths = outputPaths {
            guard outputPaths.count == options.inputFiles.count else {
                throw DLError.inputOutputCountMismatch
            }
        }

        /// Verify input files
        // NOTE: To be removed when PathArgument init checks for invalid paths.
        // Error should indicate raw string argument, not the corresponding
        // path.
        if let invalidFile = options.inputFiles.first(where: { !localFileSystem.isFile($0) }) {
            throw DLError.invalidInputFile(invalidFile)
        }

        for (i, inputFile) in options.inputFiles.enumerated() {
            /// Read IR and verify
            print("Source file:", inputFile.prettyPath())
            /// Parse
            let module = try Module.parsed(fromFile: inputFile.pathString)

            /// Run passes
            try runPass(.differentiation, on: module,
                        bypassingVerification: options.noVerify)
            if let passes = options.passes {
                for pass in passes {
                    try runPass(pass, on: module,
                                bypassingVerification: options.noVerify)
                }
            }

            /// Print IR instead of writing to file if requested
            if options.shouldPrintIR {
                print()
                print(module)
            }

            /// Otherwise, write result to IR file by default
            else {
                let path = outputPaths?[i] ?? inputFile
                try module.write(toFile: path.pathString)
            }
        }
    }

    override class func setUp(parser: ArgumentParser,
                              binder: ArgumentBinder<OptToolOptions>) {
        binder.bind(
            option: parser.add(
                option: "--no-verify", kind: Bool.self,
                usage: "Bypass verification after applying transforms"
            ),
            to: { $0.noVerify = $1 }
        )
    }
}

let tool = DLOptTool(args: Array(CommandLine.arguments.dropFirst()))
tool.runAndDiagnose()
