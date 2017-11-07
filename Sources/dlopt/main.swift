//
//  main.swift
//  dlopt
//
//  Copyright 2016-2017 Richard Wei.
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
import Foundation
import CommandLineKit
import DLCommandLineTools

let cli = CommandLineKit.CommandLine()

struct Options {
    /// File
    static let filePaths = MultiStringOption(shortFlag: "f", longFlag: "files",
                                            helpMessage: "Paths to DLVM IR source files")
    /// Print IR
    static let shouldPrintIR = BoolOption(longFlag: "print-ir",
                                          helpMessage: "Print IR after transformation instead of writing to file")

    /// Transform passes
    static let passes = MultiStringOption(shortFlag: "p", longFlag: "passes",
                                          helpMessage: "Run passes")

    /// Output
    static let outputPaths = MultiStringOption(shortFlag: "o", longFlag: "outputs",
                                               helpMessage: "Output file paths")
    /// Help
    static let needsHelp = BoolOption(shortFlag: "h", longFlag: "help",
                                      helpMessage: "Print help message")
    /// Bypass verification
    static let noVerify = BoolOption(longFlag: "no-verify",
                                     helpMessage: "Bypass verification after applying transforms")
}

cli.addOptions(Options.filePaths,
               Options.shouldPrintIR,
               Options.passes,
               Options.outputPaths,
               Options.needsHelp,
               Options.noVerify)

/// Parse command line
do { try cli.parse(strict: true) }
catch { cli.printUsage(error); exit(EXIT_FAILURE) }

/// Command line entry
func main() throws {

    guard !Options.needsHelp.wasSet else {
        print("DLVM IR Optimizer\n")
        cli.printUsage()
        return
    }

    guard let filePaths = Options.filePaths.value else {
        error("no input files; use -f to specify files")
    }

    let outputPaths = Options.outputPaths.value
    if let outputPaths = outputPaths {
        guard outputPaths.count == filePaths.count else {
            error("different numbers of inputs and outputs specified")
        }
    }

    for (i, filePath) in filePaths.enumerated() {
        /// Read IR and verify
        print("Source file:", filePath)
        /// Parse
        let module = try Module.parsed(fromFile: filePath)

        /// Run passes
        if let passes = Options.passes.value {
            for passName in passes {
                try runPass(named: passName, on: module,
                            bypassingVerification: Options.noVerify.wasSet)
            }
        }

        /// Print IR instead of writing to file if requested
        if Options.shouldPrintIR.wasSet {
            print()
            print(module)
        }

        /// Otherwise, write result to IR file by default
        else {
            let path = outputPaths?[i] ?? filePath
            try module.write(toFile: path)
        }
    }

}

do { try main() }
catch { print(error) }
