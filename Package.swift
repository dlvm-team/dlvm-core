// swift-tools-version:4.0
//
//  Package.swift
//  DLVM
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

import PackageDescription

let package = Package(
    name: "DLVM",
    products: [
        .library(name: "DLVM", type: .dynamic,
                 targets: ["DLVM", "DLParse"]),
        .library(name: "DLVMCore", type: .static,
                 targets: ["DLVM"]),
        .library(name: "DLParse", type: .static,
                 targets: ["DLParse"]),
        .library(name: "DLCommandLineTools", type: .static,
                 targets: ["DLCommandLineTools"]),
        .executable(name: "dlopt",
                    targets: ["dlopt"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-package-manager",
                 .branch("swift-5.1-branch")),
        .package(url: "https://github.com/dlvm-team/CoreTensor", from: "0.7.2")
    ],
    targets: [
        .target(name: "DLVM", dependencies: ["CoreTensor"]),
        .target(name: "DLParse", dependencies: ["DLVM"]),
        .target(name: "DLCommandLineTools", dependencies: [
            "SPMUtility", "DLVM", "DLParse"
        ]),
        .target(name: "dlopt", dependencies: [
            "DLVM", "DLParse", "DLCommandLineTools"
        ]),
        .testTarget(name: "DLVMTests", dependencies: ["DLVM"]),
        .testTarget(name: "DLParseTests", dependencies: [
            "DLVM", "DLParse"
        ]),
    ],
    swiftLanguageVersions: [4]
)
