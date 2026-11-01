//
//  CreateChartTool.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/11/01.
//

import Charts
import FoundationModels
import SwiftUI

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

extension CGImage {
    var pngData: Data? {
        let rep = NSBitmapImageRep(cgImage: self)
        return rep.representation(using: .png, properties: [:])
    }
}

enum ChartRequestProcessor {

    static func call(
        arguments: CreateChartTool.ToolInput,
        outputOption: CreateChartTool.OutputOption
    ) async throws
        -> CreateChartTool.Output
    {
        let plots: [CreateChartTool.ResolvedPlot]
        do {
            plots = try arguments.plots.map(
                CreateChartTool.ResolvedPlot.init
            )
        } catch {
            return .failure(
                "Error resolving plot's data source: \(error.localizedDescription)"
            )
        }

        let chartContent = self.chartContent(plots)

        if let onChartGenerated = outputOption.onChartGenerated {
            onChartGenerated(AnyChartContent(chartContent))
        }

        /// `ChartContent` has to be converted to `AnyChartContent` so that it can become sendable
        guard
            let image = await self.imageForChart(AnyChartContent(chartContent))
        else {
            return .failure("Fail to get image from chart.")
        }

        let (destination, error) = saveImage(
            image,
            directory: outputOption.outputDirectory
        )

        if let error { return .failure(error) }

        return .success(image: .init(image), destination: destination?.path())
    }

    private static func saveImage(_ image: CGImage, directory: URL?)
        -> (destination: URL?, error: String?)
    {
        guard let directory else { return (nil, nil) }
        guard let data = image.pngData else {
            return (nil, "Fail to get image data.")
        }
        let destination = self.resolveDestination(directory: directory)

        do {
            try data.write(to: destination)
            return (destination, nil)
        } catch {
            return (nil, "Fail to save image: \(error.localizedDescription)")
        }
    }

    private static func fileExist(_ url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path())
    }

    private static func resolveDestination(directory: URL) -> URL {
        var destination = directory.appending(
            path: "\(Int(Date().timeIntervalSince1970)).png"
        )
        var loopCount = 1
        while fileExist(destination) {
            destination = URL.temporaryDirectory.appending(
                path: "\(Int(Date().timeIntervalSince1970))_\(loopCount).png"
            )
            if !fileExist(destination) { break }
            loopCount += 1
        }

        return destination
    }

    @MainActor
    private static func imageForChart<C: ChartContent>(
        _ content: C
    ) -> CGImage? {
        let chart = self.createChart(content)
        let renderer = ImageRenderer(content: chart)
        renderer.scale = 1
        return renderer.cgImage
    }

    static func loadDataFromCSV(
        _ source: CreateChartTool.FileDataSource
    ) throws -> CreateChartTool.DiscreteDataSource {
        let dataFrame = try CSVProcessor.load(
            source.csvPath,
            columns: [source.xColName, source.yColName]
        )
        let data = try CSVProcessor.getDataPoints(
            dataFrame: dataFrame,
            xCol: source.xColName,
            yCol: source.yColName
        )
        return data
    }

    @ContentBuilder
    private static func createChart<C: ChartContent>(
        _ content: C
    ) -> some View {
        Chart {
            content
        }
        .chartYAxis(content: {
            AxisMarks {
                AxisGridLine()
                AxisValueLabel()
            }
        })
        .chartXAxis(content: {
            AxisMarks {
                AxisGridLine()
                AxisValueLabel()
            }
        })
        .padding(.all, 16)
        .frame(width: 600, height: 400)
        .background(.background)
    }

    @ChartContentBuilder
    private static func chartContent(
        _ plots: [CreateChartTool.ResolvedPlot]
    ) -> some ChartContent {
        ForEach(plots.enumerated(), id: \.offset) { _, plot in
            ForEach(plot.dataPoints) { item in
                switch plot.type {
                case .line:
                    lineMark(
                        item,
                        xType: plot.xAxisDataType,
                        yType: plot.yAxisDataType
                    )
                    .foregroundStyle(.primary)
                    .interpolationMethod(.catmullRom)
                case .point:
                    pointMark(
                        item,
                        xType: plot.xAxisDataType,
                        yType: plot.yAxisDataType
                    )
                }
            }
        }
    }

    @ChartContentBuilder
    private static func lineMark(
        _ item: CreateChartTool.SingleValueData,
        xType: CreateChartTool.DataValueType,
        yType: CreateChartTool.DataValueType
    ) -> some ChartContent {
        let formatter = ISO8601DateFormatter()

        let fallback = LineMark(
            x: .value("", item.x),
            y: .value("", item.y)
        )

        switch (xType, yType) {
        case (.string, .string):
            fallback
        case (.string, .number):
            if let number = Float(item.y) {
                LineMark(
                    x: .value("", item.x),
                    y: .value("", number)
                )
            } else {
                fallback
            }
        case (.string, .isoDate):
            if let date = formatter.date(from: item.y) {
                LineMark(
                    x: .value("", item.x),
                    y: .value("", date)
                )
            } else {
                fallback
            }
        case (.number, .string):
            if let number = Float(item.x) {
                LineMark(
                    x: .value("", number),
                    y: .value("", item.y)
                )
            } else {
                fallback
            }
        case (.number, .number):
            if let x = Float(item.x), let y = Float(item.y) {
                LineMark(
                    x: .value("", x),
                    y: .value("", y)
                )
            } else {
                fallback
            }

        case (.number, .isoDate):
            if let x = Float(item.x),
                let y = formatter.date(from: item.y)
            {
                LineMark(
                    x: .value("", x),
                    y: .value("", y)
                )
            } else {
                fallback
            }

        case (.isoDate, .string):
            if let number = formatter.date(from: item.x) {
                LineMark(
                    x: .value("", number),
                    y: .value("", item.y)
                )
            } else {
                fallback
            }

        case (.isoDate, .number):
            if let x = formatter.date(from: item.x),
                let y = Float(item.y)
            {
                LineMark(
                    x: .value("", x),
                    y: .value("", y)
                )
            } else {
                fallback
            }

        case (.isoDate, .isoDate):
            if let x = formatter.date(from: item.x),
                let y = formatter.date(from: item.y)
            {
                LineMark(
                    x: .value("", x),
                    y: .value("", y)
                )
            } else {
                fallback
            }
        }
    }

    @ChartContentBuilder
    private static func pointMark(
        _ item: CreateChartTool.SingleValueData,
        xType: CreateChartTool.DataValueType,
        yType: CreateChartTool.DataValueType
    ) -> some ChartContent {
        let formatter = ISO8601DateFormatter()

        let fallback = PointMark(
            x: .value("", item.x),
            y: .value("", item.y)
        )

        switch (xType, yType) {
        case (.string, .string):
            fallback
        case (.string, .number):
            if let number = Float(item.y) {
                PointMark(
                    x: .value("", item.x),
                    y: .value("", number)
                )
            } else {
                fallback
            }
        case (.string, .isoDate):
            if let date = formatter.date(from: item.y) {
                PointMark(
                    x: .value("", item.x),
                    y: .value("", date)
                )
            } else {
                fallback
            }
        case (.number, .string):
            if let number = Float(item.x) {
                PointMark(
                    x: .value("", number),
                    y: .value("", item.y)
                )
            } else {
                fallback
            }
        case (.number, .number):
            if let x = Float(item.x), let y = Float(item.y) {
                PointMark(
                    x: .value("", x),
                    y: .value("", y)
                )
            } else {
                fallback
            }

        case (.number, .isoDate):
            if let x = Float(item.x),
                let y = formatter.date(from: item.y)
            {
                PointMark(
                    x: .value("", x),
                    y: .value("", y)
                )
            } else {
                fallback
            }

        case (.isoDate, .string):
            if let number = formatter.date(from: item.x) {
                PointMark(
                    x: .value("", number),
                    y: .value("", item.y)
                )
            } else {
                fallback
            }

        case (.isoDate, .number):
            if let x = formatter.date(from: item.x),
                let y = Float(item.y)
            {
                PointMark(
                    x: .value("", x),
                    y: .value("", y)
                )
            } else {
                fallback
            }

        case (.isoDate, .isoDate):
            if let x = formatter.date(from: item.x),
                let y = formatter.date(from: item.y)
            {
                PointMark(
                    x: .value("", x),
                    y: .value("", y)
                )
            } else {
                fallback
            }
        }
    }
}
