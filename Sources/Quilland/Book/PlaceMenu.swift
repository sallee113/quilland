import AppKit
import QuillandCore

/// The places of the book as menu items for the "Add…" menus of the Events and Research cards. With more than one world the places are grouped under the
/// name of their world (the worlds and the places in them in alphabetical order, a place inside another one as "parent › place"); with one world it is a plain list.
enum PlaceMenu {
    /// The items for the places `include` accepts; choosing one calls `choose` with the place's id.
    static func items(in worlds: WorldStore, include: (String) -> Bool, choose: @escaping (String) -> Void) -> [NSMenuItem] {
        func sorted(_ list: [(String, String)]) -> [(String, String)] { list.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending } }
        let groups: [(world: String, places: [(String, String)])] = worlds.worlds.compactMap { w in
            guard let wid = w.id else { return nil }
            let places = worlds.entries.filter { $0.world == wid }.compactMap { e -> (String, String)? in
                guard let id = e.id, include(id) else { return nil }
                return (worlds.path(of: id).dropFirst().joined(separator: " › "), id)
            }
            return places.isEmpty ? nil : (w.name ?? "", sorted(places))
        }.sorted { $0.world.localizedStandardCompare($1.world) == .orderedAscending }
        // (Places that belong to no world that is known are listed last, so none is lost.)
        let known = Set(worlds.worlds.compactMap(\.id))
        let loose = sorted(worlds.entries.filter { !known.contains($0.world ?? "") }.compactMap { e in e.id.flatMap { include($0) ? (worlds.path(of: $0).joined(separator: " › "), $0) : nil } })

        var out: [NSMenuItem] = []
        let grouped = groups.count + (loose.isEmpty ? 0 : 1) > 1
        for g in groups {
            if grouped { out.append(heading(g.world)) }
            for (title, id) in g.places { out.append(item(title, id, indent: grouped, choose)) }
        }
        if !loose.isEmpty {
            if grouped { out.append(heading("")) }
            for (title, id) in loose { out.append(item(title, id, indent: grouped, choose)) }
        }
        return out
    }

    private static func heading(_ title: String) -> NSMenuItem {
        let h = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        h.isEnabled = false
        h.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
        return h
    }

    private static func item(_ title: String, _ id: String, indent: Bool, _ choose: @escaping (String) -> Void) -> NSMenuItem {
        let i = ClosureMenuItem(title: title) { choose(id) }
        if indent { i.indentationLevel = 1 }
        return i
    }

    /// For the checks: the titles of a menu's items, with whether each is a heading.
    static func titles(of menu: NSMenu?) -> [(title: String, heading: Bool)] { (menu?.items ?? []).map { ($0.title, !($0 is ClosureMenuItem)) } }
}
