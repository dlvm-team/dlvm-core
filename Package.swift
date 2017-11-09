// swift-tools-version:4.0
//
//  Package.swift
//  DLVM
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

import PackageDescription

let package = Package(
    name: "DLVM",
    products: [
        .library(name: "DLVM", type: .dynamic,
                 targets: ["DLVM", "DLVMCodeGen", "DLParse"]),
        .library(name: "DLVMCore", type: .static,
                 targets: ["DLVM"]),
        .library(name: "DLVMCodeGen", type: .static,
                 targets: ["DLVMCodeGen"]),
        .library(name: "DLParse", type: .static,
                 targets: ["DLParse"]),
        .executable(name: "dlopt",
                    targets: ["dlopt"]),
        .executable(name: "dlc",
                    targets: ["dlc"]),
    ],
    dependencies: [
        .package(url: "https://github.com/rxwei/LLVM_C", from: "2.1.0"),
        .package(url: "https://github.com/rxwei/CommandLine", from: "4.0.0"),
        .package(url: "https://github.com/dlvm-team/CoreTensor", from: "0.6.2")
    ],
    targets: [
        .target(name: "CoreOp", dependencies: ["CoreTensor"]),
        .target(name: "CoreCompute", dependencies: ["CoreTensor", "CoreOp"]),
        .target(name: "DLVM", dependencies: ["CoreTensor", "CoreOp", "CoreCompute"]),
        .target(name: "DLVMCodeGen", dependencies: ["DLVM"]),
        .target(name: "DLParse", dependencies: ["DLVM"]),
        .target(name: "DLCommandLineTools", dependencies: [
            "CommandLine", "DLVM", "DLVMCodeGen", "DLParse"
        ]),
        .target(name: "dlopt", dependencies: [
            "DLVM", "DLParse", "DLCommandLineTools"
        ]),
        .target(name: "dlc", dependencies: [
            "DLVM", "DLVMCodeGen", "DLParse", "DLCommandLineTools"
        ]),
        .testTarget(name: "DLVMTests", dependencies: [ "DLVM" ]),
        .testTarget(name: "DLParseTests", dependencies: [
            "DLVM", "DLParse"
        ]),
    ],
    swiftLanguageVersions: [ 4 ]
)
