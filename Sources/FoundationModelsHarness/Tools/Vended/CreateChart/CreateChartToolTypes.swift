//
//  CreateChartToolType.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/11/01.
//

import Charts
import Foundation
import FoundationModels

extension CreateChartTool {
    // MARK: - protocol conformation types
    @Generable(
        description: """
            The chart to create that can contain multiple plots stacking on top of each other.
            Chart and Plot are NOT the same.
            One Chart contains one or more plots.
            """
    )
    public struct ToolInput: Sendable {
        @Guide(
            description: """
                The plots in the chart stacking on top of each other. 
                The ones come later will be at top. 
                **ALL** plots belong to the same chart.
                """,
            .minimumCount(1)
        )
        public var plots: [ChartPlot]
    }

    public enum ToolOutput: PromptRepresentable {
        case success(
            image: Attachment<ImageAttachmentContent>?,
            destination: String?
        )
        case failure(String)

        public var promptRepresentation: Prompt {
            switch self {
            case .success(let attachment, let path):
                return Prompt {
                    if let attachment {
                        attachment.promptRepresentation
                    }
                    if let path {
                        "saved to \(path)"
                    }
                    if path == nil, attachment == nil {
                        "Chart created successfully."
                    }
                }
            case .failure(let string):
                return Prompt("Error creating chart: \(string)")
            }
        }
    }

    // MARK: - helper types
    public enum OutputOption: Sendable {
        case image(outputDirectory: URL)
        case swiftUIView(onChartGenerated: @Sendable (AnyChartContent) -> Void)
        case both(
            outputDirectory: URL,
            onChartGenerated: @Sendable (AnyChartContent) -> Void
        )

        var outputDirectory: URL? {
            switch self {
            case .image(let outputDirectory):
                return outputDirectory
            case .swiftUIView(_):
                return nil
            case .both(let outputDirectory, _):
                return outputDirectory
            }
        }

        var onChartGenerated: (@Sendable (AnyChartContent) -> Void)? {
            switch self {
            case .image(_):
                return nil
            case .swiftUIView(let onChartGenerated):
                return onChartGenerated
            case .both(_, let onChartGenerated):
                return onChartGenerated
            }
        }
    }

    // TODO: - (1) add style configuration for each plot type
    // https://levelup.gitconnected.com/swift-charts-master-marks-and-charts-styling-13ac23302c16
    // Line: .interpolationMethod(.catmullRom), .lineStyle(by: .value("", data.category.rawValue))
    // point: .symbolSize(by: .value("", data.category.rawValue)),foregroundStyle, .symbol
    // TODO: - (2) add other plot type: bar(direction: BarDirection), area
    @Generable(description: "Plot type")
    public enum PlotType: Sendable {
        case line
        case point
        /// for pie (sector), the x value will be used as the foreground style, and the y value will be the angle
        case pie
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
                    return try ChartRequestProcessor.loadDataFromCSV(source)
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

    struct ResolvedPlot: Sendable {
        var type: CreateChartTool.PlotType
        var dataPoints: [CreateChartTool.SingleValueData]
        var xAxisDataType: CreateChartTool.DataValueType
        var yAxisDataType: CreateChartTool.DataValueType

        init(_ chartPlot: CreateChartTool.ChartPlot) throws {
            self.type = chartPlot.type
            let dataSource = try chartPlot.data.discreteData
            self.dataPoints = dataSource.dataPoints
            self.xAxisDataType = dataSource.xAxisDataType
            self.yAxisDataType = dataSource.yAxisDataType
        }
    }
}
