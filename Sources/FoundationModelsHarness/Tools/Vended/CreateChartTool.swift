//
//  CreateChartTool.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/11/01.
//

import Charts
import FoundationModels
import SwiftUI

public struct CreateChartTool: Tool {
    public let name: String = "create_chart"
    public let description: String =
        "Create chart from either discrete data or csv file."

    // TODO: - (1) add style configuration for each plot type
    // https://levelup.gitconnected.com/swift-charts-master-marks-and-charts-styling-13ac23302c16
    // Line: .interpolationMethod(.catmullRom), .lineStyle(by: .value("", data.category.rawValue))
    // point: .symbolSize(by: .value("", data.category.rawValue)),foregroundStyle, .symbol
    // TODO: - (2) add other plot type: pie, bar(direction: BarDirection), area
    @Generable()
    public enum PlotType: Sendable {
        case line
        case point
    }

    @Generable()
    public enum BarDirection: Sendable {
        case horizontal
        case vertical
    }

    public struct ChartStyleConfiguration: Sendable {

    }
    public
        struct RangeValueData: Sendable
    {

    }

    @Generable(description: "A data point on the chart")
    public struct SingleValueData: Identifiable, Sendable {
        public let id = UUID()

        @Guide(description: "x value of the data point.")
        public var x: String

        @Guide(description: "y value of the data point.")
        public var y: String

    }

    @Generable()
    public enum DataSource: Sendable {
        case discrete(DiscreteDataSource)
        case file(FileDataSource)

        public var discreteData: DiscreteDataSource {
            get throws {
                switch self {
                case .discrete(let source):
                    return source
                case .file(let source):
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
            }
        }
    }

    @Generable()
    public struct DiscreteDataSource: Sendable {
        @Guide(description: "Data points to create the chart from.")
        public var dataPoints: [SingleValueData]

        @Guide(description: "x-axis data type.")
        public var xAxisDataType: DataValueType

        @Guide(description: "y-axis data type.")
        public var yAxisDataType: DataValueType
    }

    @Generable(description: "Data from a csv file.")
    public struct FileDataSource: Sendable {
        @Guide(description: "Path to the data source csv file.")
        public var csvPath: String

        @Guide(
            description:
                "The column to be used as x value. The **exact** name as it shows up in the file."
        )
        public var xColName: String

        @Guide(
            description:
                "The column to be used as y value. The **exact** name as it shows up in the file."
        )
        public var yColName: String
    }

    @Generable()
    public enum DataValueType: Sendable {
        case string
        case number
        case isoDate

        public init(_ type: any Any.Type, sampleValue: String?) {
            if type is Int.Type {
                self = .number
                return
            }
            if type is String.Type {
                if let sampleValue,
                    (try? Date(sampleValue, strategy: .iso8601)) != nil
                {
                    self = .isoDate
                } else {
                    self = .string
                }
                return
            }
            if type is Double.Type {
                self = .number
                return
            }

            self = .string
        }
    }

    @Generable(description: "A plot on a chart.")
    public struct ChartPlot: Sendable {
        @Guide(description: "plot type.")
        public var type: PlotType

        @Guide(
            description: """
                Data source, either discrete data points with `DiscreteDataSource`, or csv file with `FileDataSource`. 
                - Do NOT make up data. 
                - If user wants a chart from a path, then they want a chart using the data from the that file. Not asking you to make that path itself a data point.
                """
        )
        public var data: DataSource
    }

    private struct ResolvedPlot: Sendable {
        var type: PlotType
        var dataPoints: [SingleValueData]
        var xAxisDataType: DataValueType
        var yAxisDataType: DataValueType

        init(_ chartPlot: ChartPlot) throws {
            self.type = chartPlot.type
            let dataSource = try chartPlot.data.discreteData
            self.dataPoints = dataSource.dataPoints
            self.xAxisDataType = dataSource.xAxisDataType
            self.yAxisDataType = dataSource.yAxisDataType
        }
    }

    // MARK: - protocol implementation
    @Generable(
        description:
            "The chart to create that can contain multiple plots stacking on top of each other"
    )
    public struct ChartInput: Sendable {
        @Guide(
            description:
                "The plots in the chart stacking on top of each other. The ones come later will be at top.",
            .minimumCount(1)
        )
        public var plots: [ChartPlot]
    }

    public enum Output: PromptRepresentable {

        case success(
            image: Attachment<ImageAttachmentContent>,
            destination: String?
        )
        case failure(String)

        public var promptRepresentation: Prompt {
            switch self {
            case .success(let attachment, let path):
                return Prompt {
                    attachment.promptRepresentation
                    if let path {
                        "saved to \(path)"
                    }
                }
            case .failure(let string):
                return Prompt("Error creating chart: \(string)")
            }
        }
    }

    public func call(arguments: ChartInput) async throws -> Output {
        print(#function, arguments)
        do {
            guard
                let image = try await Self.getChartImage(arguments.plots)
            else {
                return .failure("Fail to get image data from chart.")
            }

            let destination = self.resolveDestination()

            if let data = image.pngData,
                (try? data.write(to: destination)) != nil
            {
                return .success(
                    image: .init(image),
                    destination: destination.path()
                )
            }

            return .success(image: .init(image), destination: nil)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func fileExist(_ url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path())
    }

    private func resolveDestination() -> URL {
        var destination = URL.temporaryDirectory.appending(
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
    private static func getChartImage(
        _ plots: [ChartPlot]
    ) throws
        -> CGImage?
    {
        let plots: [ResolvedPlot] = try plots.map(ResolvedPlot.init)
        let view = createChart(plots)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage
    }

    @ContentBuilder
    private static func createChart(
        _ plots: [ResolvedPlot]
    ) -> some View {
        Chart {
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
    private static func lineMark(
        _ item: SingleValueData,
        xType: DataValueType,
        yType: DataValueType
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
        _ item: SingleValueData,
        xType: DataValueType,
        yType: DataValueType
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

extension CGImage {
    var pngData: Data? {
        let rep = NSBitmapImageRep(cgImage: self)
        return rep.representation(using: .png, properties: [:])
    }
}
