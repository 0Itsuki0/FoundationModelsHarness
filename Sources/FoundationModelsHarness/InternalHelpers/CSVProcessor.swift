//
//  CSVProcessor.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/11/01.
//

import Foundation
import TabularData

enum CSVProcessor {
    enum Error: LocalizedError {
        case colNotExist([String])

        var errorDescription: String? {
            switch self {
            case .colNotExist(let cols):
                "Columns [\(cols.joined(separator: ", "))] does not exist."
            }
        }
    }

    static func load(_ path: String, columns: [String]) throws -> DataFrame {
        let url = URL(filePath: path)
        return try DataFrame(
            contentsOfCSVFile: url,
            columns: columns
        )
    }

    static func getDataPoints(dataFrame: DataFrame, xCol: String, yCol: String)
        throws -> CreateChartTool.DiscreteDataSource
    {
        var nonExistColumns: [String] = []
        if !dataFrame.containsColumn(xCol) { nonExistColumns.append(xCol) }
        if !dataFrame.containsColumn(yCol) { nonExistColumns.append(yCol) }

        guard nonExistColumns.isEmpty
        else {
            throw Error.colNotExist(nonExistColumns)
        }

        let dataPoints: [CreateChartTool.SingleValueData] = dataFrame.rows
            .compactMap { row -> CreateChartTool.SingleValueData? in
                guard let x = row[xCol], let y = row[yCol] else {
                    return nil
                }
                return .init(x: String(describing: x), y: String(describing: y))
            }

        guard
            let xCol = dataFrame.columns.first(where: { $0.name == xCol }),
            let yCol = dataFrame.columns.first(where: { $0.name == yCol })
        else {
            throw Error.colNotExist(nonExistColumns)
        }

        let xValueType: CreateChartTool.DataValueType = .init(
            xCol.wrappedElementType,
            sampleValue: dataPoints.first?.x
        )

        let yValueType: CreateChartTool.DataValueType = .init(
            yCol.wrappedElementType,
            sampleValue: dataPoints.first?.y
        )

        return .init(
            dataPoints: dataPoints,
            xAxisDataType: xValueType,
            yAxisDataType: yValueType
        )
    }
}
