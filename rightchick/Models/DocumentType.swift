import Foundation

nonisolated enum DocumentType: String, CaseIterable, Identifiable, Sendable {
    case word
    case powerPoint
    case excel

    var id: Self { self }

    var displayName: String {
        switch self {
        case .word: "Word"
        case .powerPoint: "PowerPoint"
        case .excel: "Excel"
        }
    }

    var fileExtension: String {
        switch self {
        case .word: "docx"
        case .powerPoint: "pptx"
        case .excel: "xlsx"
        }
    }

    var templateResourceName: String {
        switch self {
        case .word: "BlankWord"
        case .powerPoint: "BlankPowerPoint"
        case .excel: "BlankExcel"
        }
    }

    var newDocumentName: String { "新建 \(displayName) 文档" }
}
