//
//  SectionDetailView.swift
//  kindling
//

import SwiftUI

enum HomeDestination: Hashable, Identifiable {
    case collection(Int)
    case events

    var id: String {
        switch self {
        case .collection(let id): "collection-\(id)"
        case .events: "events"
        }
    }
}

struct SectionDetailView: View {
    let title: String
    let subtitle: String
    let items: [CollectionItemWrapper]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedFilters: Set<SectionFilter> = []

    private let figmaGray = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    private let preferredCategoryOrder = ["restaurants", "cafes", "bars"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if !availableFilters.isEmpty {
                    filterBar
                        .padding(.top, 12)
                }

                LazyVStack(spacing: 20) {
                    ForEach(filteredItems) { item in
                        Card(card: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                footer
                    .padding(.top, 32)
                    .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .top) { gradient }
        }
        .scrollIndicators(.hidden)
        .background((colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
    }

    // MARK: - Header

    private var gradient: some View {
        Image(colorScheme == .dark ? "gradient dark" : "gradient light")
            .resizable()
            .scaledToFill()
            .frame(height: 380)
            .frame(maxWidth: .infinity)
            .clipped()
            .ignoresSafeArea(edges: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(subtitle)
                .font(.system(size: 16))
                .tracking(-0.4)
                .foregroundStyle(.primary)
                .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: - Filters

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(availableFilters, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func filterChip(_ filter: SectionFilter) -> some View {
        let isSelected = selectedFilters.contains(filter)
        return Button {
            toggle(filter)
        } label: {
            Text(label(for: filter))
                .font(.system(size: 16))
                .tracking(-0.4)
                .foregroundStyle(.primary)
        }
        .if(isSelected) {
            $0.buttonStyle(.glassProminent).tint(.primary)
        }
        .if(!isSelected) {
            $0.buttonStyle(.glass).tint(.primary)
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 24) {
            Text(filteredItems.isEmpty ? "nothing matches these filters :)" : "you’ve reached the end :)")
                .font(.system(size: 16))
                .tracking(-0.16)
                .foregroundStyle(figmaGray)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("return to home")
                        .font(.system(size: 16))
                        .tracking(-0.4)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.glass)
            .tint(.primary)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Filtering

    private var availableFilters: [SectionFilter] {
        var result: [SectionFilter] = []
        if items.contains(where: { ($0.ideas?.open_hours?.isEmpty == false) }) {
            result.append(.openNow)
        }

        var categories = Set<String>()
        for item in items {
            if let locationType = item.ideas?.location_type, !locationType.isEmpty {
                let label = normalizedCategory(locationType)
                if !label.isEmpty { categories.insert(label) }
            }
        }

        let foodCount = items.filter { $0.ideas?.type?.lowercased() == "food" }.count
        if foodCount > 0, foodCount * 2 >= items.count {
            for category in preferredCategoryOrder where items.contains(where: { matches($0, category: category) }) {
                categories.insert(category)
            }
        }

        let ordered =
            preferredCategoryOrder.filter { categories.contains($0) }
            + categories.filter { !preferredCategoryOrder.contains($0) }.sorted()
        result.append(contentsOf: ordered.map { .category($0) })
        return result
    }

    private var filteredItems: [CollectionItemWrapper] {
        let categories = selectedFilters.compactMap { filter -> String? in
            if case .category(let name) = filter { return name }
            return nil
        }
        let openNow = selectedFilters.contains(.openNow)

        return items.filter { item in
            if openNow && !isOpenNow(item) { return false }
            if !categories.isEmpty && !categories.contains(where: { matches(item, category: $0) }) {
                return false
            }
            return true
        }
    }

    private func toggle(_ filter: SectionFilter) {
        let animation: Animation? = reduceMotion ? nil : AnimationConstants.springFast
        withAnimation(animation) {
            if selectedFilters.contains(filter) {
                selectedFilters.remove(filter)
            } else {
                selectedFilters.insert(filter)
            }
        }
    }

    private func label(for filter: SectionFilter) -> String {
        switch filter {
        case .openNow: "open now"
        case .category(let name): name
        }
    }

    private func isOpenNow(_ item: CollectionItemWrapper) -> Bool {
        guard let hours = item.ideas?.open_hours else { return false }
        return resolveOpenStatus(from: hours)?.isOpen == true
    }

    private func matches(_ item: CollectionItemWrapper, category: String) -> Bool {
        if let locationType = item.ideas?.location_type, !locationType.isEmpty {
            if normalizedCategory(locationType) == category { return true }
            if locationType.lowercased().contains(singular(category)) { return true }
        }

        let haystack = [item.ideas?.location_type, item.ideas?.venue, item.ideas?.name]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        switch category {
        case "cafes":
            return haystack.contains("cafe") || haystack.contains("coffee") || haystack.contains("café")
        case "bars":
            return (haystack.contains("bar") && !haystack.contains("barista"))
                || haystack.contains("pub")
        case "restaurants":
            if haystack.contains("restaurant") { return true }
            let isFood = item.ideas?.type?.lowercased() == "food"
            let looksCafe = haystack.contains("cafe") || haystack.contains("coffee") || haystack.contains("café")
            let looksBar = (haystack.contains("bar") && !haystack.contains("barista")) || haystack.contains("pub")
            return isFood && !looksCafe && !looksBar
        default:
            return haystack.contains(singular(category))
        }
    }

    private func normalizedCategory(_ locationType: String) -> String {
        let stripped = locationType.unicodeScalars
            .filter { scalar in
                !(scalar.properties.isEmoji && scalar.properties.isEmojiPresentation)
                    && !scalar.properties.isEmojiModifier
                    && scalar.value != 0xFE0F
                    && scalar.value != 0x200D
            }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if stripped.contains("coffee") || stripped.contains("cafe") || stripped.contains("café") {
            return "cafes"
        }
        if stripped.contains("restaurant") { return "restaurants" }
        if stripped.contains("bar") { return "bars" }
        if stripped.contains("bakery") || stripped.contains("dessert") { return "bakeries" }
        if stripped.isEmpty { return stripped }
        if stripped.hasSuffix("s") { return stripped }
        if stripped.hasSuffix("y"),
            let last = stripped.dropLast().last,
            !"aeiou".contains(last)
        {
            return String(stripped.dropLast()) + "ies"
        }
        return stripped + "s"
    }

    private func singular(_ plural: String) -> String {
        if plural.hasSuffix("ies") { return String(plural.dropLast(3)) + "y" }
        if plural.hasSuffix("s") { return String(plural.dropLast()) }
        return plural
    }
}

private enum SectionFilter: Hashable {
    case openNow
    case category(String)
}
