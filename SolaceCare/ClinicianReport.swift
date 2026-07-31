import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Clinician PDF export
//
// One-tap chart-note summary: status, 7-day mood, behavioral-activation lift,
// the patient's self-guided plan (when shared), active care-plan activities,
// and recent updates. Rendered locally with UIGraphicsPDFRenderer; the file is
// produced lazily when the clinician actually shares it. Every page carries a
// "self-reported app data, not a medical record" footer.

/// Lazily renders the PDF when shared (ShareLink-compatible).
struct ClinicianReportFile: Transferable {
    let snapshot: CareSnapshot?
    let feed: [CareUpdate]
    let ssiPlan: SSIPlanSummary?
    let activities: [CarePlanActivity]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { report in
            let url = try ClinicianReportPDF.render(snapshot: report.snapshot,
                                                    feed: report.feed,
                                                    ssiPlan: report.ssiPlan,
                                                    activities: report.activities)
            return SentTransferredFile(url)
        }
    }
}

enum ClinicianReportPDF {
    // US Letter, 72 dpi.
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 56
    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }

    private static let ink = UIColor(red: 0.15, green: 0.25, blue: 0.16, alpha: 1)
    private static let body = UIColor(red: 0.33, green: 0.40, blue: 0.31, alpha: 1)
    private static let muted = UIColor(red: 0.51, green: 0.58, blue: 0.48, alpha: 1)
    private static let rule = UIColor(red: 0.86, green: 0.90, blue: 0.82, alpha: 1)

    static func render(snapshot: CareSnapshot?, feed: [CareUpdate],
                       ssiPlan: SSIPlanSummary?, activities: [CarePlanActivity]) throws -> URL {
        let name = snapshot?.patientName ?? "Patient"
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        let data = renderer.pdfData { ctx in
            var composer = Composer(ctx: ctx)
            composer.beginPage()

            // Header
            composer.text("Solace Care Summary", font: .systemFont(ofSize: 21, weight: .semibold), color: ink)
            composer.space(2)
            composer.text("\(name)  ·  Generated \(Date().formatted(date: .long, time: .shortened))",
                          font: .systemFont(ofSize: 10.5), color: muted)
            composer.divider()

            // Status
            if let s = snapshot {
                composer.section("Status")
                composer.keyValue("Check-in streak", "\(s.streak) days")
                composer.keyValue("Activities this week", "\(s.wins) of \(s.weeklyGoal) goal")
                if s.afterCount > 0 {
                    composer.keyValue("Mood lift after activity",
                                      "\(s.liftedCount) of \(s.afterCount) post-activity check-ins improved")
                }
                composer.keyValue("Last update", s.updatedAt.formatted(date: .abbreviated, time: .shortened))

                // 7-day mood
                composer.section("Mood, last 7 days (self-reported, aphasia-adapted scale)")
                composer.moodWeek(s.week)
            } else {
                composer.section("Status")
                composer.text("No patient data has synced yet.", font: .systemFont(ofSize: 11), color: body)
            }

            // Patient's self-guided plan
            if let plan = ssiPlan {
                composer.section("Patient's self-guided plan (shared with consent)")
                composer.keyValue("Completed", plan.completedAt.formatted(date: .long, time: .omitted))
                composer.keyValue("Working on", plan.topStruggle)
                composer.keyValue("Hoping to", plan.topHope)
                for (i, action) in plan.actions.enumerated() {
                    composer.keyValue("Action \(i + 1)", action)
                }
                composer.keyValue("Support person", plan.supportPerson)
                composer.keyValue("If/then plan",
                                  "If \(plan.innerObstacle.lowercased()) shows up → \(plan.obstacleResponse.lowercased())")
                if plan.preReadiness >= 0 && plan.postReadiness >= 0 {
                    composer.keyValue("Readiness (0–10)",
                                      "\(plan.preReadiness) before → \(plan.postReadiness) after the session")
                }
            }

            // Active care-plan activities
            if !activities.isEmpty {
                composer.section("Active care-plan activities (care-team approved)")
                for activity in activities.prefix(6) {
                    composer.bullet("\(activity.label)\(activity.isPT ? "  [PT]" : ""): \(activity.instruction)")
                }
            }

            // Recent updates
            if !feed.isEmpty {
                composer.section("Recent updates")
                for update in feed.prefix(10) {
                    composer.bullet("\(update.date.formatted(date: .abbreviated, time: .shortened)): \(update.text)")
                }
            }

            composer.finishPage()
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Solace Care Summary for \(name).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Layout engine (y-cursor with automatic page breaks)

    private struct Composer {
        let ctx: UIGraphicsPDFRendererContext
        var y: CGFloat = 0

        mutating func beginPage() {
            ctx.beginPage()
            y = margin
        }

        mutating func ensure(_ needed: CGFloat) {
            if y + needed > pageSize.height - margin - 26 {
                finishPage()
                beginPage()
            }
        }

        func finishPage() {
            let footer = NSAttributedString(
                string: "Self-reported data from the Solace app. Not a medical record.",
                attributes: [.font: UIFont.systemFont(ofSize: 8.5), .foregroundColor: muted])
            footer.draw(at: CGPoint(x: margin, y: pageSize.height - margin + 10))
        }

        mutating func text(_ string: String, font: UIFont, color: UIColor, indent: CGFloat = 0) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2.5
            let attributed = NSAttributedString(string: string, attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
            ])
            let width = contentWidth - indent
            let height = attributed.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
            ).height.rounded(.up)
            ensure(height)
            attributed.draw(with: CGRect(x: margin + indent, y: y, width: width, height: height),
                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            y += height
        }

        mutating func space(_ points: CGFloat) { y += points }

        mutating func divider() {
            space(10)
            ensure(12)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
            rule.setStroke()
            path.lineWidth = 1
            path.stroke()
            space(4)
        }

        mutating func section(_ title: String) {
            space(14)
            ensure(24)
            text(title.uppercased(), font: .systemFont(ofSize: 9.5, weight: .bold), color: muted)
            space(4)
        }

        mutating func keyValue(_ key: String, _ value: String) {
            ensure(16)
            let keyString = NSAttributedString(string: key, attributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: muted,
            ])
            keyString.draw(at: CGPoint(x: margin, y: y + 1))
            let startY = y
            text(value, font: .systemFont(ofSize: 11), color: ink, indent: 150)
            y = max(y, startY + 15)
            space(3)
        }

        mutating func bullet(_ string: String) {
            ensure(14)
            NSAttributedString(string: "•", attributes: [
                .font: UIFont.systemFont(ofSize: 11), .foregroundColor: muted,
            ]).draw(at: CGPoint(x: margin, y: y))
            text(string, font: .systemFont(ofSize: 10.5), color: body, indent: 14)
            space(3)
        }

        /// Seven filled circles, colored by mood, with weekday initials.
        mutating func moodWeek(_ week: [Int]) {
            ensure(64)
            let moodColors: [UIColor] = [
                UIColor(red: 0.48, green: 0.55, blue: 0.44, alpha: 1),   // good
                UIColor(red: 0.60, green: 0.61, blue: 0.39, alpha: 1),   // okay
                UIColor(red: 0.80, green: 0.64, blue: 0.29, alpha: 1),   // low
                UIColor(red: 0.75, green: 0.46, blue: 0.29, alpha: 1),   // hard
                UIColor(red: 0.66, green: 0.33, blue: 0.23, alpha: 1),   // very low
            ]
            let moodWords = ["Good", "Okay", "Low", "Hard", "Very low"]
            let letters = ["S", "M", "T", "W", "T", "F", "S"]
            let cal = Calendar.current
            let step: CGFloat = 58
            let diameter: CGFloat = 18

            for (i, level) in week.enumerated() {
                let x = margin + CGFloat(i) * step
                let circle = UIBezierPath(ovalIn: CGRect(x: x, y: y, width: diameter, height: diameter))
                if level >= 0 && level < moodColors.count {
                    moodColors[level].setFill()
                    circle.fill()
                } else {
                    rule.setStroke()
                    circle.lineWidth = 1.2
                    circle.stroke()
                }
                let day = cal.date(byAdding: .day, value: i - 6, to: Date()) ?? Date()
                let label = i == 6 ? "Today" : letters[cal.component(.weekday, from: day) - 1]
                let word = level >= 0 && level < moodWords.count ? moodWords[level] : "—"
                NSAttributedString(string: label, attributes: [
                    .font: UIFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: muted,
                ]).draw(at: CGPoint(x: x, y: y + diameter + 4))
                NSAttributedString(string: word, attributes: [
                    .font: UIFont.systemFont(ofSize: 8), .foregroundColor: body,
                ]).draw(at: CGPoint(x: x, y: y + diameter + 15))
            }
            y += diameter + 30
        }
    }
}
