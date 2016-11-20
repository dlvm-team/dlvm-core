import PackageDescription

let package = Package(
    name: "LLNM",
    dependencies: [
        .Package(url: "https://github.com/rxwei/cuda-swift", majorVersion: 1, minor: 2),
        .Package(url: "https://github.com/rxwei/CCUDA", majorVersion: 1, minor: 4)
    ]
)
