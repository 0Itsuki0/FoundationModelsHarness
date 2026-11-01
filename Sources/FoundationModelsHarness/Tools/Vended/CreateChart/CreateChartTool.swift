//
//  CreateChartTool.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/11/01.
//

import Charts
import FoundationModels

/// CreateChartTool: A tool to create chart (plots) from either discrete data points, or from csv files.
///
/// Specifically, this tool can be used for visualizing *unknown* data user provides in two ways.
/// - create and save chart images to `outputDirectory`
/// - display SwiftUI Charts by specifying `onChartGenerated`
public struct CreateChartTool: Tool {
    public let name: String = "create_chart"
    public let description: String =
        "Create a chart from discrete data points or csv file that can contain multiple plots."

    private let outputOption: CreateChartTool.OutputOption

    // MARK: - protocol implementation
    public typealias Arguments = CreateChartTool.ToolInput
    public typealias Output = CreateChartTool.ToolOutput

    public func call(arguments: Arguments) async throws -> Output {
        return try await ChartRequestProcessor.call(
            arguments: arguments,
            outputOption: outputOption
        )
    }
}

extension CreateChartTool {
    /// Create a `CreateChartTool` where the chart will be saved as an image in the specified directory
    public init(outputDirectory: URL) {
        self.outputOption = .image(
            outputDirectory: outputDirectory
        )
    }

    /// Create a `CreateChartTool` where the chart will be used for dynamic SwiftUI Display.
    /// ex:
    /// ```
    /// // SwiftUI View
    /// @State private var chartContent: AnyChartContent?
    /// if let chartContent {
    ///     Chart { chartContent }
    /// }
    ///
    /// // Tool creation
    /// let tool = CreateChartTool(onChartGenerated: { chart in
    ///     Task { @MainActor [chart] in chartContent = chart }
    /// })
    /// ```
    public init(
        onChartGenerated: @escaping @Sendable (AnyChartContent) -> Void
    ) {
        self.outputOption = .swiftUIView(onChartGenerated: onChartGenerated)
    }

    /// Create a `CreateChartTool` where the chart will be saved as an image, as well as used for dynamic SwiftUI Display.
    public init(
        outputDirectory: URL,
        onChartGenerated: @escaping @Sendable (AnyChartContent) -> Void
    ) {
        self.outputOption = .both(
            outputDirectory: outputDirectory,
            onChartGenerated: onChartGenerated
        )
    }
}
