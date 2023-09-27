//
//  RswiftGeneratePublicResources.swift
//  
//
//  Created by Tom Lokhorst on 2022-10-19.
//

import Foundation
import PackagePlugin

@main
struct RswiftGeneratePublicResources: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        
        /// On Xcode cloud we don't have write access to the derived data folder, which is the default output location for the `R.generated.swift` file.
        /// With this change we are saving the file to a `tmp` folder, which we access to by default both on local machines and on Xcode Cloud
        ///
        ///  - Note: It's better-engineering to tie this behaviour to a build setting like `R_SWIFT_USE_TMP_FOLDER` to be backwards compatible with `R.swift` itself but it doesn't hurt us this way either
        let outputDirectoryPath = Path(NSTemporaryDirectory())
            .appending(subpath: target.name)

        try FileManager.default.createDirectory(atPath: outputDirectoryPath.string, withIntermediateDirectories: true)

        let rswiftPath = outputDirectoryPath.appending(subpath: "R.generated.swift")

        let sourceFiles = target.sourceFiles
            .filter { $0.type == .resource || $0.type == .unknown }
            .map(\.path.string)

        let inputFilesArguments = sourceFiles
            .flatMap { ["--input-files", $0 ] }

        let bundleSource = target.kind == .generic ? "module" : "finder"
        let description = "\(target.kind) module \(target.name)"

        return [
            .buildCommand(
                displayName: "R.swift generate resources for \(description)",
                executable: try context.tool(named: "rswift").path,
                arguments: [
                    "generate", rswiftPath.string,
                    "--input-type", "input-files",
                    "--bundle-source", bundleSource,
                    "--access-level", "public",
                ] + inputFilesArguments,
                outputFiles: [rswiftPath]
            ),
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension RswiftGeneratePublicResources: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {

        let resourcesDirectoryPath = context.pluginWorkDirectory
            .appending(subpath: target.displayName)
            .appending(subpath: "Resources")

        try FileManager.default.createDirectory(atPath: resourcesDirectoryPath.string, withIntermediateDirectories: true)

        let rswiftPath = resourcesDirectoryPath.appending(subpath: "R.generated.swift")

        let description: String
        if let product = target.product {
            description = "\(product.kind) \(target.displayName)"
        } else {
            description = target.displayName
        }

        return [
            .buildCommand(
                displayName: "R.swift generate resources for \(description)",
                executable: try context.tool(named: "rswift").path,
                arguments: [
                    "generate", rswiftPath.string,
                    "--target", target.displayName,
                    "--input-type", "xcodeproj",
                    "--bundle-source", "finder",
                    "--access-level", "public",
                ],
                outputFiles: [rswiftPath]
            ),
        ]
    }
}

#endif

public extension ProcessInfo {
    var isLikelyXcodeCloudEnvironment: Bool {
        // https://developer.apple.com/documentation/xcode/environment-variable-reference
        let requiredKeys: Set = [
            "CI",
            "CI_BUILD_ID",
            "CI_BUILD_NUMBER",
            "CI_BUNDLE_ID",
            "CI_COMMIT",
            "CI_DERIVED_DATA_PATH",
            "CI_PRODUCT",
            "CI_PRODUCT_ID",
            "CI_PRODUCT_PLATFORM",
            "CI_PROJECT_FILE_PATH",
            "CI_START_CONDITION",
            "CI_TEAM_ID",
            "CI_WORKFLOW",
            "CI_WORKSPACE",
            "CI_XCODE_PROJECT",
            "CI_XCODE_SCHEME",
            "CI_XCODEBUILD_ACTION"
        ]
        
        return requiredKeys.isSubset(of: environment.keys)
    }
}
