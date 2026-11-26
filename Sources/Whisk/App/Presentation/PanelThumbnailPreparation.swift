import AppKit

/// Owns the background consumers for the next ordinary panel presentation.
/// Visible cards use the same stores, so opening mid-decode joins the work.
@MainActor
final class PanelThumbnailPreparation {
    private let images: ImageThumbnailStore
    private let files: FileThumbnailStore
    private let openingItems: () -> [ClipboardItem]
    private var imageTickets: [UUID] = []
    private var fileTickets: [UUID] = []
    private var panelVisible = false
    private var underPressure = false
    private var preparationScheduled = false

    private var canPrepare: Bool {
        !panelVisible && !underPressure && !images.isProtected && !images.lightweightMode
    }

    init(
        images: ImageThumbnailStore, files: FileThumbnailStore, lightweight: Bool, protected: Bool,
        openingItems: @escaping () -> [ClipboardItem]
    ) {
        self.images = images
        self.files = files
        self.openingItems = openingItems
        images.setLightweightMode(lightweight)
        setPrivacy(protected)
        if lightweight { release() }
    }

    /// Include the partially visible last card and one more for the first scroll.
    static func slotLimit(width: CGFloat, stride: CGFloat) -> Int {
        guard width > 0, stride > 0, width.isFinite, stride.isFinite else { return 0 }
        return min(24, Int(ceil(min(24, width / stride))) + 1)
    }

    func setPanelVisible(_ visible: Bool) {
        guard panelVisible != visible else { return }
        panelVisible = visible
        if !visible {
            if canPrepare { schedule() } else { release() }
        }
    }

    func setLightweightMode(_ enabled: Bool) {
        guard images.lightweightMode != enabled else { return }
        images.setLightweightMode(enabled)
        if enabled {
            if panelVisible { cancelPreparation() } else { release() }
        } else {
            schedule()
        }
    }

    func setPrivacy(_ protected: Bool) {
        images.setPrivacy(protected)
        files.setPrivacy(protected)
        if protected { cancelPreparation() } else { schedule() }
    }

    func setMemoryPressure(_ pressured: Bool) {
        let wasPressured = underPressure
        underPressure = pressured
        if pressured { release() } else if wasPressured { schedule() }
    }

    func schedule() {
        guard canPrepare, !preparationScheduled else { return }
        preparationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.preparationScheduled = false
            if self.canPrepare { self.prepare() }
        }
    }

    private func prepare() {
        var requests: [ImageThumbnailRequest] = []
        var paths: [String] = []
        for item in openingItems() {
            let content: BinaryContent
            switch item.payload {
            case .image(let bytes): content = .inline(bytes)
            case .storedImage(let reference): content = .stored(reference)
            case .fileReferences(let names):
                if let first = names.first, !paths.contains(first) { paths.append(first) }
                continue
            default: continue
            }
            requests.append(
                ImageThumbnailRequest(id: item.id, content: content, maxPixelSize: ImageThumbnailRequest.cardPixelLimit)
            )
        }
        images.keepOpeningCards(Set(requests.map(\.id)))
        files.keepOpeningFiles(Set(paths))
        // Subscribe before releasing the previous batch. A new copy shifts
        // the row by one without cancelling the other thumbnails in flight.
        let nextImages = requests.compactMap { images.load($0, priority: .low) { _ in } }
        let nextFiles = paths.compactMap { files.load($0) }
        cancelPreparation()
        imageTickets = nextImages
        fileTickets = nextFiles
    }

    private func cancelPreparation() {
        imageTickets.forEach(images.cancel)
        fileTickets.forEach(files.cancel)
        imageTickets.removeAll()
        fileTickets.removeAll()
    }

    func release() {
        images.releaseCache()
        files.releaseCache()
        imageTickets.removeAll()
        fileTickets.removeAll()
    }
}
