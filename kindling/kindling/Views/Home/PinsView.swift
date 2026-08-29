//
//  PinsView.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/24/26.
//

import Foundation
import CoreLocation
import Supabase
import SwiftUI

private let figmaGray = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
private let homeSectionPreviewLimit = 5
private let homeSectionPreviewHeight: CGFloat = 250
private let nearbyRadiusMiles = 20.0

private struct MappedIdea: Identifiable {
    let item: SavedIdea
    let coordinate: CLLocationCoordinate2D
    let mapName: String?

    var id: Int { item.id }

    var displayName: String {
        mapName ?? item.ideas?.name ?? "Saved idea"
    }
}

private struct PinsDerivedSnapshot {
    let allLocationItems: [SavedIdea]
    let foodItems: [SavedIdea]
    let nearbyLocationItems: [SavedIdea]
    let filteredEventItems: [SavedIdea]
    let pastEventItems: [SavedIdea]
    let filteredLocationItems: [SavedIdea]
    let visibleIdeas: [MappedIdea]

    static let empty = PinsDerivedSnapshot(
        allLocationItems: [],
        foodItems: [],
        nearbyLocationItems: [],
        filteredEventItems: [],
        pastEventItems: [],
        filteredLocationItems: [],
        visibleIdeas: []
    )
}

struct KindlingTranslucentSheetBackground: View {
    var opacity: Double = 0.72

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if opacity < 1 {
                    Rectangle()
                        .fill(.regularMaterial)
                }

                Color(uiColor: .systemBackground)
                    .opacity(opacity)

                if opacity < 1 {
                    // Keep the map legible through the surface while adding a
                    // quiet charcoal/warm-gray tint that belongs to kindling.
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                Color.white.opacity(0.04),
                                Color.black.opacity(0.12),
                                Color(red: 104 / 255, green: 77 / 255, blue: 57 / 255).opacity(0.08),
                            ]
                            : [
                                Color.white.opacity(0.22),
                                Color.black.opacity(0.04),
                                Color(red: 154 / 255, green: 111 / 255, blue: 76 / 255).opacity(0.06),
                            ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    RadialGradient(
                        colors: [
                            Color(red: 208 / 255, green: 122 / 255, blue: 66 / 255).opacity(0.08),
                            .clear,
                        ],
                        center: UnitPoint(x: 0.82, y: 0.66),
                        startRadius: 0,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.72
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

private enum SheetSectionDestination: Hashable, Identifiable {
    case food
    case nearby
    case events
    case allSavedPlaces
    case pastEvents

    var id: Self { self }
}

private enum SheetDestination: Hashable {
    case section(SheetSectionDestination)
    case idea(Int)

    var isIdea: Bool {
        if case .idea = self { return true }
        return false
    }
}

@Observable
private final class PinsLocationManager: NSObject, CLLocationManagerDelegate {
    var location: CLLocation?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways else { return }
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

struct PinsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(UserSettings.self) private var userSettings
    @Environment(ScreenshotIndexingController.self) private var screenshotIndexing

    @State private var collections: [CollectionWrapper] = []
    @State private var onboardingHomeItems: [ItemWrapper] = []
    @State private var mappedIdeas: [MappedIdea] = []
    @State private var resolvingIdeaIDs = Set<Int>()
    @State private var failedIdeaIDs = Set<Int>()
    @State private var locationManager = PinsLocationManager()
    @State private var searchText = ""
    @State private var selectedIdeaID: Int?
    @State private var mapCenter: CLLocationCoordinate2D?
    // At this zoom the map is roughly ten miles wide on a standard iPhone.
    @State private var mapZoom: Float = 11.5
    @State private var centerRequestID = 0
    @State private var hasSetInitialCamera = false
    @State private var mapHeight: CGFloat = 0
    @State private var isLoading = true
    @State private var detailIdea: SavedIdea?
    @State private var sheetPath: [SheetDestination] = []
    @State private var isDiscoverySheetPresented = true
    @State private var isSettingsSheetPresented = false
    @State private var isLocationControlVisible = true
    // Start discovery at the native half-sheet detent. Navigation can still
    // return to whichever detent the user was previously viewing.
    @State private var discoveryDetent: PresentationDetent = .fraction(0.55)
    @State private var discoveryDetentBeforeNavigation: PresentationDetent?
    @State private var derivedSnapshot = PinsDerivedSnapshot.empty

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                map

                topChrome
            }
            .overlay(alignment: .bottomTrailing) {
                mapUserLocationControl
            }
            .ignoresSafeArea(edges: .bottom)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(isPresented: $isDiscoverySheetPresented) {
                sheetContent
                    .presentationDetents(
                        [.height(110), .fraction(0.55), .large],
                        selection: $discoveryDetent
                    )
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.clear)
                    // Keep the native iOS sheet curvature and inset, including
                    // the updated Liquid Glass half-sheet treatment.
                    .presentationCornerRadius(nil)
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.55)))
                    .presentationContentInteraction(.resizes)
                    .interactiveDismissDisabled(true)
            }
        }
        .task {
            locationManager.requestLocation()
            if let userID = supabase.auth.currentUser?.id {
                onboardingHomeItems = OnboardingHomeCache.load(for: userID)
                rebuildDerivedSnapshot()
            }
            await loadCollections()
            let scanAddedIdeas = await screenshotIndexing.scan()
            // Refresh only when the scan actually persisted new ideas, then
            // resolve saved place IDs so nearby results can be complete.
            if scanAddedIdeas {
                await loadCollections()
            }
            await resolveMissingPlaces()
        }
        .onChange(of: locationManager.location) { _, newLocation in
            rebuildDerivedSnapshot()
            guard let newLocation, !hasSetInitialCamera, selectedIdeaID == nil else { return }
            centerMapOnUser(newLocation.coordinate)
        }
        .onChange(of: searchText) { _, _ in
            rebuildDerivedSnapshot()
            selectedIdeaID = nil
            mapCenter = nil
        }
        .onChange(of: selectedIdeaID) { _, newValue in
            if newValue == nil {
                if case .idea(_) = sheetPath.last {
                    sheetPath.removeLast()
                    detailIdea = nil
                }
                if discoveryDetentBeforeNavigation == nil {
                    discoveryDetent = .height(110)
                } else if sheetPath.isEmpty {
                    restoreDiscoveryDetentIfNeeded()
                }
                isDiscoverySheetPresented = true
            } else {
                if let newValue {
                    // Map markers are keyed by the idea id. `collection_items.id`
                    // is a different identity, so matching on `$0.id` can open
                    // the wrong screenshot/card (or the previously selected
                    // one) when those sequences happen to overlap.
                    if let item = derivedSnapshot.allLocationItems.first(where: { $0.id == newValue }) {
                        showIdeaInSheet(item)
                    }
                }
            }
        }
        .onChange(of: sheetPath) { oldPath, path in
            let leftIdeaDestination = oldPath.last?.isIdea == true
                && path.last?.isIdea != true
            let willClearSelectedIdea = leftIdeaDestination && selectedIdeaID != nil

            if leftIdeaDestination {
                selectedIdeaID = nil
                detailIdea = nil
            }

            if path.isEmpty && !willClearSelectedIdea {
                restoreDiscoveryDetentIfNeeded()
            }
        }
        .onChange(of: discoveryDetent) { _, newDetent in
            transitionLocationControl(to: newDetent)
        }
    }

    private var map: some View {
        GoogleMapView(
            markers: derivedSnapshot.visibleIdeas.map {
                GoogleMapMarkerData(
                    id: $0.id,
                    coordinate: $0.coordinate,
                    title: $0.displayName,
                    emoji: $0.item.ideas?.location_emoji ?? "✦"
                )
            },
            center: mapCenter,
            zoom: mapZoom,
            centerRequestID: centerRequestID,
            isInteractive: true,
            selectedID: selectedIdeaID,
            onSelect: {
                // A marker tap is an intentional map-to-detail transition;
                // bring the discovery sheet up enough to show the detail.
                rememberDiscoveryDetentBeforeNavigation()
                discoveryDetent = .fraction(0.55)
                selectedIdeaID = $0
            },
            onDeselect: { selectedIdeaID = nil }
        )
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { mapHeight = proxy.size.height }
                    .onChange(of: proxy.size) { _, size in mapHeight = size.height }
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel("Map of saved ideas")
    }

    private var mapUserLocationControl: some View {
        GeometryReader { proxy in
            VStack {
                Spacer()

                HStack {
                    Spacer()
                    Button {
                        if let coordinate = locationManager.location?.coordinate {
                            centerMapOnUser(coordinate)
                        } else {
                            locationManager.requestLocation()
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 42)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Center map on your location")
                    .padding(.trailing, 16)
                    .padding(.bottom, mapUserLocationButtonBottomPadding(for: proxy.size.height))
                    .opacity(isLocationControlVisible ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.28),
                        value: discoveryDetent
                    )
                }
            }
            .allowsHitTesting(discoveryDetent != .large)
        }
    }

    private func mapPin(_ mapped: MappedIdea) -> some View {
        let isSelected = selectedIdeaID == mapped.id
        let glassStyle: Glass = isSelected ? .identity : .regular
        return VStack(spacing: 0) {
            pinEmoji(mapped, isSelected: isSelected)
                .background(isSelected ? Color.white : Color.clear, in: Circle())
                .glassEffect(glassStyle, in: Circle())
                .overlay(
                    Circle().stroke(Color.white, lineWidth: isSelected ? 3 : 0)
                )
                .frame(width: 48, height: 48)
                .scaleEffect(isSelected ? 1 : 0.9)

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.72))
                .offset(y: -2)
                .opacity(isSelected ? 1 : 0)
        }
        .accessibilityLabel(mapped.displayName)
    }

    private func pinEmoji(_ mapped: MappedIdea, isSelected: Bool) -> some View {
        Text(mapped.item.ideas?.location_emoji ?? "✦")
            .font(.system(size: isSelected ? 24 : 18))
            .frame(width: isSelected ? 48 : 38, height: isSelected ? 48 : 38)
            .foregroundStyle(.primary)
    }

    private var topChrome: some View {
        VStack(spacing: 12) {
            HStack {
                Image(colorScheme == .dark ? "kindling white" : "kindling black")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 22)
                Spacer()
                Button {
                    isSettingsSheetPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 13, weight: .medium))
                        Text(userSettings.displayName)
                            .font(.system(size: 16))
                            .tracking(-0.4)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.glass)
                .tint(.primary)
                .accessibilityHint("Opens settings")
                .accessibilityLabel("Account for \(userSettings.displayName)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.primary)
            TextField(
                "",
                text: $searchText,
                prompt: Text("cozy cafes to study from...").foregroundColor(figmaGray)
            )
            .tint(.primary)
            .foregroundStyle(.primary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 16))
        .tracking(-0.4)
        .padding(.horizontal, 16)
        .frame(height: 50)
        .glassEffect(.regular, in: Capsule())
    }

    private var sheetContent: some View {
        NavigationStack(path: $sheetPath) {
            ZStack {
                KindlingTranslucentSheetBackground(
                    opacity: isDiscoverySheetTranslucent ? 0.72 : 1
                )

                discoverySheet
            }
            // Keep the navigation bar in the hierarchy before a destination
            // is pushed. The native back button can then appear without
            // changing the sheet's safe-area geometry mid-transition.
            .ignoresSafeArea(edges: .top)
            .background(Color.clear)
            .scrollContentBackground(.hidden)
            .toolbarVisibility(.visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: SheetDestination.self) { destination in
                switch destination {
                case .section(let section):
                    sectionPage(section)
                case .idea(let ideaID):
                    if let detailIdea {
                        IdeaView(
                            card: detailIdea,
                            function: { _ in await loadCollections() },
                            allowsDeletion: !detailIdea.isOnboardingCached,
                            isPreview: isDiscoverySheetTranslucent
                        )
                        // `detailIdea` is separate state from the navigation
                        // path. Force SwiftUI to give each idea a fresh view
                        // state so its screenshot loader cannot retain the
                        // image from the prior selection.
                        .id(ideaID)
                        .toolbarVisibility(.visible, for: .navigationBar)
                    }
                }
            }
        }
        .sheet(isPresented: $isSettingsSheetPresented) {
            NavigationStack {
                AccountView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(36)
            .presentationBackground(Color(uiColor: .systemBackground))
        }
    }

    private var isDiscoverySheetTranslucent: Bool {
        discoveryDetent != .large
    }

    @ViewBuilder
    private func sectionPage(_ destination: SheetSectionDestination) -> some View {
        switch destination {
        case .food:
            SectionDetailView(
                title: "#nomnomnom",
                subtitle: "food you saved.",
                items: derivedSnapshot.foodItems,
                onBack: dismissSectionPage,
                onSelect: showIdeaInSheet
            )
        case .nearby:
            SectionDetailView(
                title: "things near you",
                subtitle: "within 20 miles, closest first",
                items: derivedSnapshot.nearbyLocationItems,
                onBack: dismissSectionPage,
                onSelect: showIdeaInSheet
            )
        case .events:
            SectionDetailView(
                title: "events coming up in the calendar week",
                subtitle: "upcoming events this week",
                items: derivedSnapshot.filteredEventItems,
                onBack: dismissSectionPage,
                onSelect: showIdeaInSheet
            )
        case .allSavedPlaces:
            SectionDetailView(
                title: "all saved places",
                subtitle: "every place you saved",
                items: derivedSnapshot.filteredLocationItems,
                onBack: dismissSectionPage,
                onSelect: showIdeaInSheet
            )
        case .pastEvents:
            SectionDetailView(
                title: "past events",
                subtitle: "events you saved that have passed",
                items: derivedSnapshot.pastEventItems,
                onBack: dismissSectionPage,
                onSelect: showIdeaInSheet
            )
        }
    }

    private func dismissSectionPage() {
        guard case .section = sheetPath.last else { return }
        sheetPath.removeLast()
    }

    private func openSectionPage(_ destination: SheetSectionDestination) {
        rememberDiscoveryDetentBeforeNavigation()
        sheetPath.append(.section(destination))
    }

    private var discoverySheet: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                if !derivedSnapshot.foodItems.isEmpty {
                    discoverySection(
                        title: "#nomnomnom",
                        items: derivedSnapshot.foodItems,
                        action: { openSectionPage(.food) }
                    )
                }

                discoverySection(
                    title: "things near you",
                    items: derivedSnapshot.nearbyLocationItems,
                    action: { openSectionPage(.nearby) }
                )

                if !derivedSnapshot.filteredEventItems.isEmpty {
                    discoverySection(
                        title: "events coming up in the calendar week",
                        items: derivedSnapshot.filteredEventItems,
                        action: { openSectionPage(.events) }
                    )
                }

                discoverySection(
                    title: "all saved places",
                    items: derivedSnapshot.filteredLocationItems,
                    action: { openSectionPage(.allSavedPlaces) }
                )

                if !derivedSnapshot.pastEventItems.isEmpty {
                    discoverySection(
                        title: "past events",
                        items: derivedSnapshot.pastEventItems,
                        action: { openSectionPage(.pastEvents) }
                    )
                }
            }
            .opacity(isDiscoverySheetCollapsed ? 0 : 1)
            .allowsHitTesting(!isDiscoverySheetCollapsed)
            .accessibilityHidden(isDiscoverySheetCollapsed)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .scrollDisabled(discoveryDetent != .large)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaBar(edge: .top, spacing: 0) {
            searchBar
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)
        }
    }

    private var isDiscoverySheetCollapsed: Bool {
        discoveryDetent == .height(110)
    }

    private func rebuildDerivedSnapshot() {
        let allItems = derivedLocationItems
        let eventItems = deduplicatedSavedIdeas(
            allCollectionItems
                .filter { isEvent($0) }
        )
        let normalizedQuery = query
        let matchesQuery: (SavedIdea) -> Bool = { item in
            guard !normalizedQuery.isEmpty else { return true }
            let idea = item.ideas
            return [idea?.name, idea?.location_type]
                .contains { $0?.lowercased().contains(normalizedQuery) == true }
        }

        let parsedDates = Dictionary(
            uniqueKeysWithValues: eventItems.map { ($0.id, Self.parsedEventDate(for: $0)) }
        )
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: today, duration: 7 * 24 * 60 * 60)

        func isUpcoming(_ item: SavedIdea) -> Bool {
            guard let parsed = parsedDates[item.id] ?? nil else { return false }
            let eventDay = calendar.startOfDay(for: parsed.date)
            guard eventDay >= today, eventDay < week.end else { return false }
            return !parsed.hasTime || parsed.date >= now
        }

        func isPast(_ item: SavedIdea) -> Bool {
            guard let parsed = parsedDates[item.id] ?? nil else { return false }
            let eventDay = calendar.startOfDay(for: parsed.date)
            return eventDay < today || (eventDay == today && parsed.hasTime && parsed.date < now)
        }

        func sortedEvents(_ items: [SavedIdea], ascending: Bool) -> [SavedIdea] {
            items.sorted { lhs, rhs in
                let lhsDate = parsedDates[lhs.id] ?? nil
                let rhsDate = parsedDates[rhs.id] ?? nil
                switch (lhsDate?.date, rhsDate?.date) {
                case let (left?, right?):
                    return ascending ? left < right : left > right
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return false
                }
            }
        }

        let coordinatesByIdeaID = Dictionary(
            mappedIdeas.map { ($0.id, $0.coordinate) },
            uniquingKeysWith: { first, _ in first }
        )
        let radiusMeters = nearbyRadiusMiles * 1_609.344
        let nearby: [(item: SavedIdea, distance: CLLocationDistance)]
        if let userLocation = locationManager.location {
            nearby = allItems.compactMap { item in
                guard let coordinate = coordinatesByIdeaID[item.id] else { return nil }
                let distance = userLocation.distance(
                    from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                )
                guard distance <= radiusMeters else { return nil }
                return (item, distance)
            }
        } else {
            nearby = []
        }

        derivedSnapshot = PinsDerivedSnapshot(
            allLocationItems: allItems,
            foodItems: allItems.filter { isFood($0) }.filter(matchesQuery),
            nearbyLocationItems: nearby.sorted { $0.distance < $1.distance }.map(\.item).filter(matchesQuery),
            filteredEventItems: sortedEvents(eventItems, ascending: true).filter(isUpcoming).filter(matchesQuery),
            pastEventItems: sortedEvents(eventItems, ascending: false).filter(isPast).filter(matchesQuery),
            filteredLocationItems: allItems.filter(matchesQuery),
            visibleIdeas: normalizedQuery.isEmpty
                ? mappedIdeas
                : mappedIdeas.filter { matchesQuery($0.item) }
        )
    }

    private static let eventDateFormats = ["yyyy-MM-dd", "MM/dd/yyyy", "MMMM d, yyyy", "MMM d, yyyy"]
    private static let eventTimeFormats = ["h:mm a", "h a", "HH:mm"]

    private struct ParsedEventDate {
        let date: Date
        let hasTime: Bool
    }

    private static func parsedEventDate(for item: SavedIdea) -> ParsedEventDate? {
        guard let dateString = item.ideas?.date?.trimmingCharacters(in: .whitespacesAndNewlines),
              !dateString.isEmpty else { return nil }

        let timeString = item.ideas?.time?.trimmingCharacters(in: .whitespacesAndNewlines)
        let locale = Locale(identifier: "en_US_POSIX")
        if let timeString, !timeString.isEmpty {
            for dateFormat in eventDateFormats {
                for timeFormat in eventTimeFormats {
                    let parser = DateFormatter()
                    parser.locale = locale
                    parser.calendar = Calendar.current
                    parser.dateFormat = "\(dateFormat) \(timeFormat)"
                    if let date = parser.date(from: "\(dateString) \(timeString)") {
                        return ParsedEventDate(date: date, hasTime: true)
                    }
                }
            }
        }

        for dateFormat in eventDateFormats {
            let parser = DateFormatter()
            parser.locale = locale
            parser.calendar = Calendar.current
            parser.dateFormat = dateFormat
            if let date = parser.date(from: dateString) {
                return ParsedEventDate(date: date, hasTime: false)
            }
        }
        return nil
    }

    private func isFood(_ item: SavedIdea) -> Bool {
        item.ideas?.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "food"
    }

    private func isEvent(_ item: SavedIdea) -> Bool {
        item.ideas?.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "event"
    }

    private func isEvent(_ item: CollectionItemWrapper) -> Bool {
        item.ideas?.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "event"
    }

    private func discoverySection(
        title: String,
        items: [SavedIdea],
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: action) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 20, weight: .medium))
                        .tracking(-0.5)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            if items.isEmpty {
                Text(isLoading ? "finding your ideas..." : "no saved ideas here yet")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .frame(height: 120)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(items.prefix(homeSectionPreviewLimit)) { item in
                            discoveryCard(item)
                        }

                        if items.count > homeSectionPreviewLimit {
                            viewMoreCard(action: action)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                .frame(height: homeSectionPreviewHeight)
            }
        }
    }

    private func viewMoreCard(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 6) {
                    Text("view all")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .font(.system(size: 16, weight: .medium))
                .tracking(-0.35)
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.primary, in: Capsule())
            }
            .frame(width: 250, height: 250)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View all")
    }

    private func discoveryCard(_ item: SavedIdea) -> some View {
        Button {
            focusOnMap(item)
        } label: {
            Card(
                card: item,
                loadsMapData: false,
                loadsPlaceDetails: true,
                loadsRemoteMedia: true,
                handlesTap: false,
                allowsDetailPresentation: false,
                allowsDeletion: false
            )
            .frame(width: 250, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func showIdeaInSheet(_ item: SavedIdea) {
        rememberDiscoveryDetentBeforeNavigation()
        detailIdea = item
        isDiscoverySheetPresented = true
        let ideaID = item.id
        if case .idea(let currentID) = sheetPath.last {
            if currentID != ideaID {
                sheetPath[sheetPath.count - 1] = .idea(ideaID)
            }
        } else {
            sheetPath.append(.idea(ideaID))
        }
    }

    private func rememberDiscoveryDetentBeforeNavigation() {
        guard sheetPath.isEmpty, discoveryDetentBeforeNavigation == nil else { return }
        discoveryDetentBeforeNavigation = discoveryDetent
    }

    private func restoreDiscoveryDetentIfNeeded() {
        guard let detent = discoveryDetentBeforeNavigation else { return }
        discoveryDetent = detent
        discoveryDetentBeforeNavigation = nil
    }

    private func focusOnMap(_ item: SavedIdea) {
        let ideaID = item.id
        if let mapped = mappedIdeas.first(where: { $0.id == ideaID }) {
            focusOnMap(mapped, presenting: item)
            return
        }

        // Resolve a card immediately when its map pin has not been loaded yet.
        guard item.ideas?.place_id != nil else {
            showIdeaInSheet(item)
            return
        }

        if resolvingIdeaIDs.contains(ideaID) {
            Task { @MainActor in
                for _ in 0..<30 {
                    if let mapped = mappedIdeas.first(where: { $0.id == ideaID }) {
                        focusOnMap(mapped, presenting: item)
                        return
                    }
                    guard resolvingIdeaIDs.contains(ideaID), !Task.isCancelled else { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }

                if let mapped = mappedIdeas.first(where: { $0.id == ideaID }) {
                    focusOnMap(mapped, presenting: item)
                } else {
                    showIdeaInSheet(item)
                }
            }
            return
        }

        resolvingIdeaIDs.insert(ideaID)
        Task { @MainActor in
            defer { resolvingIdeaIDs.remove(ideaID) }

            guard let place = await resolvePlace(for: item) else {
                showIdeaInSheet(item)
                return
            }

            guard let coordinate = place.coordinate else {
                showIdeaInSheet(item)
                return
            }

            let mapped = MappedIdea(item: item, coordinate: coordinate, mapName: place.name)
            if !mappedIdeas.contains(where: { $0.id == ideaID }) {
                mappedIdeas.append(mapped)
                rebuildDerivedSnapshot()
            }
            focusOnMap(mapped, presenting: item)
        }
    }

    private func focusOnMap(_ mapped: MappedIdea) {
        focusOnMap(mapped, presenting: nil)
    }

    private func focusOnMap(
        _ mapped: MappedIdea,
        presenting item: SavedIdea?
    ) {
        withAnimation(.easeInOut(duration: 0.45)) {
            mapZoom = 14
            centerRequestID += 1
            mapCenter = cameraCenter(for: mapped.coordinate, zoom: mapZoom)
            selectedIdeaID = mapped.id
        }

        // Keep the direct navigation path while the map recenters underneath it.
        showIdeaInSheet(item ?? mapped.item)
    }

    private func loadCollections() async {
        let signpostID = KindlingProfiling.begin(KindlingProfiling.collectionLoad)
        defer {
            KindlingProfiling.end(KindlingProfiling.collectionLoad, id: signpostID)
        }

        isLoading = true
        await migrateLegacyDefaultCollectionName()
        do {
            let fetchedCollections: [CollectionWrapper] = try await supabase
                .from("collections")
                .select("*, collection_items(*, ideas(*))")
                .execute()
                .value
            collections = fetchedCollections

            if let userID = supabase.auth.currentUser?.id {
                let fetchedItems = fetchedCollections.flatMap { $0.collection_items ?? [] }
                let confirmedLocalIDs = Set(fetchedItems.map(\.local_id))
                if !confirmedLocalIDs.isEmpty {
                    onboardingHomeItems.removeAll {
                        confirmedLocalIDs.contains($0.local_id)
                    }
                    OnboardingHomeCache.removeConfirmedItems(
                        localIDs: confirmedLocalIDs,
                        for: userID
                    )
                }
            }
            refreshMappedIdeas()
        } catch {
            dump(error)
        }
        isLoading = false
    }

    private func refreshMappedIdeas() {
        let previous = Dictionary(
            mappedIdeas.map { ($0.id, ($0.coordinate, $0.mapName)) },
            uniquingKeysWith: { current, _ in current }
        )

        mappedIdeas = derivedLocationItems.compactMap { item in
            let id = item.id
            // Coordinates are Google Places response data and stay in memory only.
            // Keep a successfully resolved pin visible while a collection
            // refresh is happening.
            guard let (coordinate, mapName) = previous[id] else { return nil }
            return MappedIdea(item: item, coordinate: coordinate, mapName: mapName)
        }
        rebuildDerivedSnapshot()
    }

    private func resolveMissingPlaces() async {
        let candidates = derivedLocationItems.filter { item in
            item.ideas?.place_id != nil
        }

        let mappedIDs = Set(mappedIdeas.map(\.id))
        let pending = candidates.filter {
            !mappedIDs.contains($0.id)
                && !resolvingIdeaIDs.contains($0.id)
                && !failedIdeaIDs.contains($0.id)
        }
        guard !pending.isEmpty else { return }

        let pendingIDs = Set(pending.map(\.id))
        resolvingIdeaIDs.formUnion(pendingIDs)
        defer { resolvingIdeaIDs.subtract(pendingIDs) }

        let results = await withTaskGroup(of: (Int, GooglePlaceDetails?).self) { group in
            var iterator = pending.makeIterator()
            for _ in 0..<min(4, pending.count) {
                guard let item = iterator.next() else { break }
                let ideaID = item.id
                group.addTask {
                    guard !Task.isCancelled else { return (ideaID, nil) }
                    return (ideaID, await self.resolvePlace(for: item))
                }
            }

            var results: [(Int, GooglePlaceDetails?)] = []
            while let result = await group.next() {
                results.append(result)
                if let item = iterator.next() {
                    let ideaID = item.id
                    group.addTask {
                        guard !Task.isCancelled else { return (ideaID, nil) }
                        return (ideaID, await self.resolvePlace(for: item))
                    }
                }
            }
            return results
        }

        guard !Task.isCancelled else { return }
        var updatedMappedIdeas = mappedIdeas
        var failedIDs: Set<Int> = []
        for (ideaID, place) in results {
            guard let place, let coordinate = place.coordinate,
                  let item = pending.first(where: { $0.id == ideaID }) else {
                failedIDs.insert(ideaID)
                continue
            }
            updatedMappedIdeas.append(
                MappedIdea(item: item, coordinate: coordinate, mapName: place.name)
            )
        }
        failedIdeaIDs.formUnion(failedIDs)
        mappedIdeas = updatedMappedIdeas
        rebuildDerivedSnapshot()
    }

    private var derivedLocationItems: [SavedIdea] {
        deduplicatedSavedIdeas(
            allCollectionItems
                .filter { !isEvent($0) }
        )
    }

    private var allCollectionItems: [CollectionItemWrapper] {
        let remoteItems = collections.flatMap { $0.collection_items ?? [] }
        let remoteLocalIDs = Set(remoteItems.map(\.local_id))
        guard let userID = supabase.auth.currentUser?.id else {
            return remoteItems
        }

        let cachedItems = onboardingHomeItems
            .filter { !remoteLocalIDs.contains($0.local_id) }
            .map { item in
                CollectionItemWrapper(
                    // Cached onboarding rows do not have collection-item IDs
                    // yet. Negative IDs keep them distinct and prevent a
                    // premature delete from targeting a real server row.
                    id: -max(1, item.id),
                    created_at: "",
                    local_id: item.local_id,
                    idea_id: item.idea_id,
                    user_id: userID,
                    collection_id: nil,
                    ideas: item.ideas
                )
            }
        return remoteItems + cachedItems
    }

    private func resolvePlace(for item: SavedIdea) async -> GooglePlaceDetails? {
        guard let placeID = item.ideas?.place_id else { return nil }
        return await GooglePlacesService.shared.details(for: placeID)
    }

    private func centerMapOnUser(_ coordinate: CLLocationCoordinate2D) {
        hasSetInitialCamera = true
        withAnimation(.easeInOut(duration: 0.45)) {
            mapZoom = 11.5
            centerRequestID += 1
            mapCenter = cameraCenter(for: coordinate, zoom: mapZoom)
        }
    }

    private func transitionLocationControl(to detent: PresentationDetent) {
        guard !reduceMotion else {
            isLocationControlVisible = detent != .large
            return
        }

        withAnimation(.easeOut(duration: 0.14)) {
            isLocationControlVisible = false
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, discoveryDetent == detent else { return }

            withAnimation(.easeOut(duration: 0.18)) {
                isLocationControlVisible = detent != .large
            }
        }
    }

    private func mapUserLocationButtonBottomPadding(for height: CGFloat) -> CGFloat {
        if discoveryDetent == .height(110) {
            // A fixed-height presentation detent also leaves room for the
            // bottom safe area. Keep the control completely above the sheet.
            return 160
        }

        // The default half-sheet covers 55% of the map. Keep the native
        // location control just above its top edge.
        if discoveryDetent == .fraction(0.55) {
            return max(126, height * 0.55 + 16)
        }

        return 16
    }

    private func cameraCenter(
        for coordinate: CLLocationCoordinate2D,
        zoom: Float
    ) -> CLLocationCoordinate2D {
        // Move the camera center south so the user's location appears roughly
        // 400 points higher, centered in the map area above the discovery sheet.
        let effectiveMapHeight = mapHeight > 0 ? Double(mapHeight) : 844
        // Scale the reference viewport to the requested zoom so card taps get
        // the same on-screen offset even though they zoom in closer.
        let zoomScale = pow(2.0, 11.5 - Double(zoom))
        let verticalOffsetMeters = 16_000 * zoomScale * 400 / effectiveMapHeight
        let metersPerLatitudeDegree = 111_320.0
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude - verticalOffsetMeters / metersPerLatitudeDegree,
            longitude: coordinate.longitude
        )
    }
}
