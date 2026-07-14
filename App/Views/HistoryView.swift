import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranscriptRecord.createdAt, order: .reverse)
    private var records: [TranscriptRecord]

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No dictations yet",
                        systemImage: "clock",
                        description: Text("Finished dictations appear here.")
                    )
                } else {
                    List {
                        ForEach(records) { record in
                            row(for: record)
                        }
                        .onDelete { offsets in
                            offsets.forEach { modelContext.delete(records[$0]) }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func row(for record: TranscriptRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.polishedText)
                .lineLimit(3)
            HStack(spacing: 8) {
                Text(record.styleName)
                Text(record.createdAt, format: .dateTime.month().day().hour().minute())
                if record.source == TranscriptRecord.Source.keyboard.rawValue {
                    Image(systemName: "keyboard")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .leading) {
            Button {
                UIPasteboard.general.string = record.polishedText
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .tint(.blue)
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: TranscriptRecord.self, inMemory: true)
}
