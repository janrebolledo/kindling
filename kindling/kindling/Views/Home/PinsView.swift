//
//  PinsView.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/24/26.
//

import Foundation
import MapKit
import Supabase
import SwiftUI

private let figmaGray = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
private let homeSectionPreviewLimit = 5

private struct MappedIdea: Identifiable {
    let item: CollectionItemWrapper
    let coordinate: CLLocationCoordinate2D
    let mapName: String?

    var id: Int { item.ideas?.id ?? item.idea_id }

    var displayName: String {
        mapName ?? item.ideas?.name ?? "Saved idea"
    }
}

private struct DiscoveryIdeaImage: View {
    let item: CollectionItemWrapper
    @State private var localImage: UIImage?
    @State private var imageRequestToken = UUID()

    private var imageLoadID: String {
        "\(item.id)-\(item.local_id)-\(item.ideas?.media_url ?? "remote")"
    }

    var body: some View {
        ZStack {
            Color.gray.opacity(0.14)

            if let mediaURL = item.ideas?.media_url,
               let url = URL(string: mediaURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error == nil {
                        ProgressView().controlSize(.small)
                    } else {
                        placeholder
                    }
                }
            } else if let localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        // A concrete render size prevents the async image from changing the
        // carousel's layout or appearing to move independently of its card.
        .frame(width: 250, height: 150)
        .clipped()
        .task(id: imageLoadID) {
            let requestToken = UUID()
            imageRequestToken = requestToken
            localImage = nil

            guard item.ideas?.media_url == nil, !item.local_id.isEmpty else { return }

            let loadedImage = try? await loadImage(from: item.local_id)
            guard !Task.isCancelled, imageRequestToken == requestToken else { return }
            localImage = loadedImage
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 24))
            .foregroundStyle(.secondary)
    }
}

private struct DiscoverySheetBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    stops: [
                        .init(color: Color(red: 202 / 255, green: 53 / 255, blue: 0).opacity(0.16), location: 0),
                        .init(color: Color(red: 228 / 255, green: 95 / 255, blue: 2 / 255).opacity(0.15), location: 0.25),
                        .init(color: Color(red: 255 / 255, green: 137 / 255, blue: 4 / 255).opacity(0.10), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.58),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.58
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum SheetSectionDestination: Hashable {
    case nomnomnom
    case nearby
    case events
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
    @State private var mappedIdeas: [MappedIdea] = []
    @State private var resolvingIdeaIDs = Set<Int>()
    @State private var failedIdeaIDs = Set<Int>()
    @State private var mapKitRequestTimes: [Date] = []
    @State private var locationManager = PinsLocationManager()
    @State private var searchText = ""
    @State private var selectedIdeaID: Int?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasSetInitialCamera = false
    @State private var mapHeight: CGFloat = 0
    @State private var isLoading = true
    @State private var detailIdea: CollectionItemWrapper?
    @State private var isShowingIdeaInSheet = false
    @State private var sectionDestination: SheetSectionDestination?
    @State private var sectionPageProgress: CGFloat = 0
    @State private var sectionDragStartProgress: CGFloat?
    @State private var isDiscoverySheetPresented = true
    @State private var isSettingsSheetPresented = false
    @State private var discoveryDetent: PresentationDetent = .fraction(0.55)
    @Namespace private var mapScope
    @Namespace private var ideaTransition

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var allLocationItems: [CollectionItemWrapper] {
        var seen = Set<Int>()
        return collections
            .flatMap { $0.collection_items ?? [] }
            .filter { item in
                guard item.ideas?.type?.lowercased() != "event" else { return false }
                let id = item.ideas?.id ?? item.idea_id
                return seen.insert(id).inserted
            }
    }

    private var visibleIdeas: [MappedIdea] {
        guard !query.isEmpty else { return mappedIdeas }
        return mappedIdeas.filter { mapped in
            let idea = mapped.item.ideas
            return [idea?.name, idea?.location_type]
                .contains { $0?.lowercased().contains(query) == true }
        }
    }

    private var nomnomnomCollection: CollectionWrapper? {
        collections.first { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "nomnomnom" }
    }

    private var nomnomnomItems: [CollectionItemWrapper] {
        guard let collection = nomnomnomCollection else { return [] }
        return filter(locationItems(for: collection, applyingSearch: false))
    }

    private var allNomnomnomItems: [CollectionItemWrapper] {
        guard let collection = nomnomnomCollection else { return [] }
        return locationItems(for: collection, applyingSearch: false)
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
            await loadCollections()
            await screenshotIndexing.scan()
            // Refresh ideas created by the scan, then resolve only a bounded
            // batch of Apple Place IDs for the map.
            await loadCollections()
            await resolveMissingPlaces()
        }
        .onChange(of: locationManager.location) { _, newLocation in
            guard let newLocation, !hasSetInitialCamera, selectedIdeaID == nil else { return }
            centerMapOnUser(newLocation.coordinate)
        }
        .onChange(of: cameraPosition) { _, newPosition in
            // MapUserLocationButton changes the camera to .userLocation
            // directly. Reapply the app's top-space framing after MapKit
            // finishes that recentering.
            guard newPosition.followsUserLocation,
                  let coordinate = locationManager.location?.coordinate else { return }
            centerMapOnUser(coordinate)
        }
        .onChange(of: searchText) { _, _ in
            selectedIdeaID = nil
            cameraPosition = .automatic
        }
        .onChange(of: selectedIdeaID) { _, newValue in
            if newValue == nil {
                if !isShowingIdeaInSheet {
                    discoveryDetent = .fraction(0.55)
                    dismissSectionPage()
                }
                isDiscoverySheetPresented = true
            } else {
                if let newValue {
                    if let item = allLocationItems.first(where: {
                        ($0.ideas?.id ?? $0.idea_id) == newValue
                    }) {
                        showIdeaInSheet(item)
                    }
                }
            }
        }
        .onChange(of: isShowingIdeaInSheet) { _, isShowing in
            if !isShowing {
                discoveryDetent = .fraction(0.55)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: selectedIdeaID)
    }

    private var map: some View {
        Map(position: $cameraPosition, selection: $selectedIdeaID, scope: mapScope) {
            ForEach(visibleIdeas) { mapped in
                Annotation(
                    mapped.displayName,
                    coordinate: mapped.coordinate,
                    anchor: .bottom
                ) {
                    mapPin(mapped)
                }
                .tag(mapped.id)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { mapHeight = proxy.size.height }
                    .onChange(of: proxy.size) { _, size in mapHeight = size.height }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { _ in
            Task { await resolveMissingPlaces() }
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
                    MapUserLocationButton(scope: mapScope)
                        .padding(.trailing, 16)
                        .padding(.bottom, mapUserLocationButtonBottomPadding(for: proxy.size.height))
                }
            }
            .opacity(discoveryDetent == .large ? 0 : 1)
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
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isSelected)
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
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground)
                    .opacity(isDiscoverySheetTranslucent ? 0.72 : 1)
                .ignoresSafeArea()

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            discoverySheet
                                .frame(width: proxy.size.width)

                            if let sectionDestination {
                                sectionPage(sectionDestination)
                                    .frame(width: proxy.size.width)
                            } else {
                                Color.clear
                                    .frame(width: proxy.size.width)
                            }
                        }
                        .offset(x: -proxy.size.width * sectionPageProgress)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                    .clipped()
                    .contentShape(Rectangle())
                    .simultaneousGesture(sectionPageGesture(width: proxy.size.width))
                }
            }
            .background(Color.clear)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $isShowingIdeaInSheet) {
                if let detailIdea {
                    IdeaView(
                        card: detailIdea,
                        function: { _ in await loadCollections() },
                        allowsDeletion: true,
                        isPreview: isDiscoverySheetTranslucent
                    )
                    .navigationTransition(
                        .zoom(sourceID: transitionID(for: detailIdea), in: ideaTransition)
                    )
                    .toolbarVisibility(.visible, for: .navigationBar)
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
        .simultaneousGesture(discoverySheetPromotionGesture)
    }

    private var isDiscoverySheetTranslucent: Bool {
        discoveryDetent != .large
    }

    private var sheetNavigationAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .timingCurve(0.32, 0.72, 0, 1, duration: 0.28)
    }

    private var sectionGestureSettleAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.3, dampingFraction: 0.8)
    }

    private var discoverySheetPromotionGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                guard discoveryDetent == .fraction(0.55),
                      value.translation.height < 0,
                      abs(value.translation.height) > abs(value.translation.width)
                else { return }

                withAnimation(
                    reduceMotion
                        ? .linear(duration: 0.01)
                        : .spring(response: 0.3, dampingFraction: 0.85)
                ) {
                    discoveryDetent = .large
                }
            }
    }

    @ViewBuilder
    private func sectionPage(_ destination: SheetSectionDestination) -> some View {
        switch destination {
        case .nomnomnom:
            SectionDetailView(
                title: "#nomnomnom",
                subtitle: subtitle(for: allNomnomnomItems),
                items: allNomnomnomItems,
                onBack: dismissSectionPage
            )
        case .nearby:
            SectionDetailView(
                title: "Things Near You",
                subtitle: "places near you",
                items: filteredLocationItems,
                onBack: dismissSectionPage
            )
        case .events:
            SectionDetailView(
                title: "events this week",
                subtitle: "what’s happening this week",
                items: filteredEventItems,
                onBack: dismissSectionPage
            )
        }
    }

    private func dismissSectionPage() {
        withAnimation(sheetNavigationAnimation) {
            sectionPageProgress = 0
        }
    }

    private func openSectionPage(_ destination: SheetSectionDestination) {
        sectionDestination = destination
        withAnimation(sheetNavigationAnimation) {
            sectionPageProgress = 1
        }
    }

    private func sectionPageGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard value.startLocation.x < 32,
                      sectionDestination != nil,
                      abs(value.translation.width) > abs(value.translation.height)
                else { return }

                if sectionDragStartProgress == nil {
                    sectionDragStartProgress = sectionPageProgress
                }

                let startProgress = sectionDragStartProgress ?? sectionPageProgress
                let translation = value.translation.width

                // A left drag opens the next page from home; a right drag
                // returns from the detail page. Keep the track attached to the
                // finger and ignore movement toward an unavailable boundary.
                if startProgress <= 0, translation >= 0 { return }
                if startProgress >= 1, translation <= 0 { return }

                sectionPageProgress = min(
                    1,
                    max(0, startProgress - translation / max(width, 1))
                )
            }
            .onEnded { value in
                defer { sectionDragStartProgress = nil }
                guard let startProgress = sectionDragStartProgress,
                      sectionDestination != nil else { return }

                let projectedProgress = startProgress
                    - value.predictedEndTranslation.width / max(width, 1)
                withAnimation(sectionGestureSettleAnimation) {
                    sectionPageProgress = projectedProgress > 0.5 ? 1 : 0
                }
            }
    }

    private var discoverySheet: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                // This stack only contains a few sections. Keeping it eager gives
                // the sheet a stable full content height when sections contain
                // nested horizontal scrollers.
                VStack(alignment: .leading, spacing: 28) {
                    if !nomnomnomItems.isEmpty {
                        discoverySection(
                            title: "#nomnomnom",
                            items: nomnomnomItems,
                            action: { openSectionPage(.nomnomnom) }
                        )
                    }

                    discoverySection(
                        title: "Things Near You",
                        items: filteredLocationItems,
                        action: { openSectionPage(.nearby) }
                    )

                    if !filteredEventItems.isEmpty {
                        discoverySection(
                            title: "events this week",
                            items: filteredEventItems,
                            action: { openSectionPage(.events) }
                        )
                    }
                }
                .opacity(isDiscoverySheetCollapsed ? 0 : 1)
                .allowsHitTesting(!isDiscoverySheetCollapsed)
                .accessibilityHidden(isDiscoverySheetCollapsed)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .background {
                    DiscoverySheetBackground()
                }
            }
            .frame(maxWidth: .infinity)
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
    }

    private var isDiscoverySheetCollapsed: Bool {
        discoveryDetent == .height(110)
    }

    private var filteredLocationItems: [CollectionItemWrapper] {
        filter(allLocationItems)
    }

    private func locationItems(
        for collection: CollectionWrapper,
        applyingSearch: Bool
    ) -> [CollectionItemWrapper] {
        let items = (collection.collection_items ?? []).filter {
            $0.ideas?.type?.lowercased() != "event"
        }
        return applyingSearch ? filter(items) : items
    }

    private var filteredEventItems: [CollectionItemWrapper] {
        var seen = Set<Int>()
        let events = collections.flatMap { $0.collection_items ?? [] }.filter { item in
            guard item.ideas?.type?.lowercased() == "event" else { return false }
            return seen.insert(item.ideas?.id ?? item.idea_id).inserted
        }
        return filter(events)
    }

    private func filter(_ items: [CollectionItemWrapper]) -> [CollectionItemWrapper] {
        guard !query.isEmpty else { return items }
        return items.filter { item in
            let idea = item.ideas
            return [idea?.name, idea?.location_type]
                .contains { $0?.lowercased().contains(query) == true }
        }
    }

    private func subtitle(for items: [CollectionItemWrapper]) -> String {
        let types = items.compactMap { $0.ideas?.type?.lowercased() }
        let foodCount = types.filter { $0 == "food" }.count
        if !types.isEmpty && foodCount * 2 >= types.count {
            return "tasty things you saved."
        }
        return "things you saved."
    }

    private func discoverySection(
        title: String,
        items: [CollectionItemWrapper],
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
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

    private func discoveryCard(_ item: CollectionItemWrapper) -> some View {
        let displayName = mappedIdeas.first {
            $0.id == (item.ideas?.id ?? item.idea_id)
        }?.displayName ?? item.ideas?.name ?? "Untitled"

        return Button {
            focusOnMap(item)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                DiscoveryIdeaImage(item: item)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(displayName)
                    .font(.system(size: 19, weight: .medium))
                    .tracking(-0.45)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.ideas?.locationTypeLabel ?? "saved place")
                    .font(.system(size: 14))
                    .tracking(-0.3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

            }
            .frame(width: 250, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(
            id: transitionID(for: item),
            in: ideaTransition
        )
    }

    private func showIdeaInSheet(_ item: CollectionItemWrapper) {
        detailIdea = item
        isDiscoverySheetPresented = true
        isShowingIdeaInSheet = true
    }

    private func focusOnMap(_ item: CollectionItemWrapper) {
        let ideaID = item.ideas?.id ?? item.idea_id
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

            guard let mapItem = await resolveMapItem(for: item) else {
                showIdeaInSheet(item)
                return
            }

            let coordinate = mapItem.location.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else {
                showIdeaInSheet(item)
                return
            }

            let mapped = MappedIdea(item: item, coordinate: coordinate, mapName: mapItem.name)
            if !mappedIdeas.contains(where: { $0.id == ideaID }) {
                mappedIdeas.append(mapped)
            }
            focusOnMap(mapped, presenting: item)
        }
    }

    private func focusOnMap(_ mapped: MappedIdea) {
        focusOnMap(mapped, presenting: nil)
    }

    private func focusOnMap(
        _ mapped: MappedIdea,
        presenting item: CollectionItemWrapper?
    ) {
        withAnimation(.easeInOut(duration: 0.45)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: mapped.coordinate,
                    latitudinalMeters: 1_200,
                    longitudinalMeters: 1_200
                )
            )
            selectedIdeaID = mapped.id
        }

        // Keep the direct navigation path while the map recenters underneath it.
        showIdeaInSheet(item ?? mapped.item)
    }

    private func transitionID(for item: CollectionItemWrapper) -> String {
        // Collection-item IDs identify the rendered source, whereas an idea can
        // appear in multiple collections and therefore have multiple sources.
        "idea-image-\(item.id)"
    }

    private func loadCollections() async {
        isLoading = true
        await migrateLegacyDefaultCollectionName()
        do {
            collections = try await supabase
                .from("collections")
                .select("*, collection_items(*, ideas(*))")
                .execute()
                .value
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

        mappedIdeas = allLocationItems.compactMap { item in
            let id = item.ideas?.id ?? item.idea_id
            // Coordinates are MapKit response data and stay in memory only.
            // Keep a successfully resolved pin visible while a collection
            // refresh is happening.
            guard let (coordinate, mapName) = previous[id] else { return nil }
            return MappedIdea(item: item, coordinate: coordinate, mapName: mapName)
        }
    }

    private func resolveMissingPlaces() async {
        let candidates = allLocationItems.filter { item in
            item.ideas?.place_id != nil
        }

        var resolvedThisPass = 0
        for item in candidates {
            guard resolvedThisPass < 6 else { break }
            let ideaID = item.ideas?.id ?? item.idea_id
            guard !mappedIdeas.contains(where: { $0.id == ideaID }),
                  !resolvingIdeaIDs.contains(ideaID),
                  !failedIdeaIDs.contains(ideaID) else { continue }

            resolvingIdeaIDs.insert(ideaID)
            defer { resolvingIdeaIDs.remove(ideaID) }
            resolvedThisPass += 1

            // A small gap plus a six-item batch prevents a map refresh from
            // creating the burst of requests that caused the throttle error.
            if resolvedThisPass > 1 {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            let cutoff = Date().addingTimeInterval(-60)
            mapKitRequestTimes.removeAll { $0 < cutoff }
            guard mapKitRequestTimes.count < 40 else { return }
            mapKitRequestTimes.append(Date())

            guard let mapItem = await resolveMapItem(for: item) else {
                failedIdeaIDs.insert(ideaID)
                continue
            }
            let coordinate = mapItem.location.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else {
                failedIdeaIDs.insert(ideaID)
                continue
            }

            mappedIdeas.append(
                MappedIdea(item: item, coordinate: coordinate, mapName: mapItem.name)
            )
        }
    }

    private func resolveMapItem(for item: CollectionItemWrapper) async -> MKMapItem? {
        let idea = item.ideas
        if let placeID = idea?.place_id,
           let identifier = MKMapItem.Identifier(rawValue: placeID) {
            let request = MKMapItemRequest(mapItemIdentifier: identifier)
            return await withCheckedContinuation { continuation in
                request.getMapItem { mapItem, _ in
                    continuation.resume(returning: mapItem)
                }
            }
        }
        return nil
    }

    private func centerMapOnUser(_ coordinate: CLLocationCoordinate2D) {
        hasSetInitialCamera = true
        withAnimation(.easeInOut(duration: 0.45)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: initialCameraCenter(for: coordinate),
                    latitudinalMeters: 24_140,
                    longitudinalMeters: 24_140
                )
            )
        }
    }

    private func mapUserLocationButtonBottomPadding(for height: CGFloat) -> CGFloat {
        if discoveryDetent == .height(110) {
            return 126
        }

        // The default half-sheet covers 55% of the map. Keep the native
        // location control just above its top edge.
        if discoveryDetent == .fraction(0.55) {
            return max(126, height * 0.55 + 16)
        }

        return 16
    }

    private func initialCameraCenter(for coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        // Move the camera center south so the user's location appears roughly
        // 400 points higher, centered in the map area above the discovery sheet.
        let effectiveMapHeight = mapHeight > 0 ? Double(mapHeight) : 844
        let verticalOffsetMeters = 24_140 * 400 / effectiveMapHeight
        let mapPoint = MKMapPoint(coordinate)
        let offset = verticalOffsetMeters * MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        return MKMapPoint(x: mapPoint.x, y: mapPoint.y + offset).coordinate
    }
}
