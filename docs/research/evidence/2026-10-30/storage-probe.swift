import Foundation
@main struct AuditProbe {
 static func main() throws {
  let directory = URL(fileURLWithPath: "/private/tmp/whisk-may-audit.XUHzFH/storage-probe", isDirectory: true)
  let database = directory.appendingPathComponent("history.sqlite")
  let store = try SQLiteHistoryStore(databaseURL: database)
  let original = History().recording(.text("before audit edit"), from: nil, rtf: Data("old formatting".utf8), at: Date(timeIntervalSince1970: 1700000000))
  try store.save(original.items)
  let id = original.items[0].id
  let edited = try EditItem(store: store)(id, text: "after audit edit", in: original)
  let reloaded = try SQLiteHistoryStore(databaseURL: database).load()
  print("memory:", edited.items[0].payload, "rtf:", edited.items[0].rtf != nil)
  print("reloaded:", reloaded[0].payload, "rtf:", reloaded[0].rtf != nil)
  print("edit survives reload:", reloaded == edited.items)
  let duplicate = original.recording(.text("before audit edit"), from: nil, rtf: Data("new formatting".utf8), at: Date(timeIntervalSince1970: 1700000001))
  print("duplicate preserves old RTF:", duplicate.items[0].rtf == original.items[0].rtf)
 }
}
