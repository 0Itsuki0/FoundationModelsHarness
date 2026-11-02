//
//  ChartRequestProcessor.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/11/01.
//

import Charts

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
                    ChartMarkBuilder.lineMark(
                        item,
                        xType: plot.xAxisDataType,
                        yType: plot.yAxisDataType
                    )
                    .foregroundStyle(.primary)
                    .interpolationMethod(.catmullRom)
                case .point:
                    ChartMarkBuilder.pointMark(
                        item,
                        xType: plot.xAxisDataType,
                        yType: plot.yAxisDataType
                    )
                case .pie:
                    ChartMarkBuilder.sectorMark(
                        item,
                        xType: plot.xAxisDataType,
                        yType: plot.yAxisDataType
                    )
                }
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
