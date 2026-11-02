//
//  ChartMarkBuilder.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/11/02.
//

import Charts

enum ChartMarkBuilder {
    @ChartContentBuilder
    static func lineMark(
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
    static func pointMark(
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

    @ChartContentBuilder
    static func sectorMark(
        _ item: CreateChartTool.SingleValueData,
        xType: CreateChartTool.DataValueType,
        yType: CreateChartTool.DataValueType
    ) -> some ChartContent {
        let formatter = ISO8601DateFormatter()

        let fallback = SectorMark(
            angle: .value("", item.y)
        ).foregroundStyle(by: .value("", item.x))

        switch (xType, yType) {
        case (.string, .string):
            fallback
        case (.string, .number):
            if let number = Float(item.y) {
                SectorMark(
                    angle: .value("", number)
                ).foregroundStyle(by: .value("", item.x))
            } else {
                fallback
            }
        case (.string, .isoDate):
            if let date = formatter.date(from: item.y) {
                SectorMark(
                    angle: .value("", date)
                ).foregroundStyle(by: .value("", item.x))
            } else {
                fallback
            }
        case (.number, .string):
            if let number = Float(item.x) {
                SectorMark(
                    angle: .value("", item.y)
                ).foregroundStyle(by: .value("", number))
            } else {
                fallback
            }
        case (.number, .number):
            if let x = Float(item.x), let y = Float(item.y) {
                SectorMark(
                    angle: .value("", y)
                ).foregroundStyle(by: .value("", x))
            } else {
                fallback
            }
        case (.number, .isoDate):
            if let x = Float(item.x),
                let y = formatter.date(from: item.y)
            {
                SectorMark(
                    angle: .value("", y)
                ).foregroundStyle(by: .value("", x))
            } else {
                fallback
            }

        case (.isoDate, .string):
            if let number = formatter.date(from: item.x) {
                SectorMark(
                    angle: .value("", item.y)
                ).foregroundStyle(by: .value("", number))
            } else {
                fallback
            }

        case (.isoDate, .number):
            if let x = formatter.date(from: item.x),
                let y = Float(item.y)
            {
                SectorMark(
                    angle: .value("", y)
                ).foregroundStyle(by: .value("", x))
            } else {
                fallback
            }

        case (.isoDate, .isoDate):
            if let x = formatter.date(from: item.x),
                let y = formatter.date(from: item.y)
            {
                SectorMark(
                    angle: .value("", y)
                ).foregroundStyle(by: .value("", x))
            } else {
                fallback
            }
        }
    }
}
