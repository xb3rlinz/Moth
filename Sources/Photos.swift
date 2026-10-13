import SwiftUI
import SwiftData
import PhotosUI
import ImageIO

// MARK: - Image processing
//
// All decoding and scaling happens off the main thread with ImageIO, which can decode a large
// photo straight to a small size without ever holding the full-resolution bitmap in memory.

enum PhotoProcessor {
    /// Longest edge, in pixels, of a photo as stored. Bigger originals are scaled down once on
    /// import so a 48-megapixel shot does not become a 10 MB database attachment.
    static let storedMaxPixel: CGFloat = 2400
    static let storedQuality: CGFloat = 0.8

    /// Decodes `data` to an image whose longest edge is at most `maxPixel`, with the camera
    /// orientation applied. Never scales up. Returns nil if the data is not a readable image.
    static func downsampledImage(from data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        var target = maxPixel
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
           let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
           width > 0, height > 0 {
            target = min(maxPixel, CGFloat(max(width, height)))
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// The bytes to store for an imported photo: downscaled, orientation-corrected JPEG.
    static func prepareForStorage(_ data: Data) -> Data? {
        guard let image = downsampledImage(from: data, maxPixel: storedMaxPixel) else { return nil }
        return image.jpegData(compressionQuality: storedQuality)
    }
}

// MARK: - Thumbnail cache

private final class ThumbnailKey: NSObject {
    let id: PersistentIdentifier

    init(_ id: PersistentIdentifier) { self.id = id }

    override var hash: Int { id.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ThumbnailKey else { return false }
        return other.id == id
    }
}

/// Keeps recently decoded thumbnails so scrolling back to a photo does not decode it again.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<ThumbnailKey, UIImage>()

    private init() {
        cache.countLimit = 150
    }

    func image(for id: PersistentIdentifier) -> UIImage? {
        cache.object(forKey: ThumbnailKey(id))
    }

    func store(_ image: UIImage, for id: PersistentIdentifier) {
        cache.setObject(image, forKey: ThumbnailKey(id))
    }
}

// MARK: - Thumbnail

/// A square preview of one photo. Shows a progress indicator while decoding and an explicit
/// "can't load" tile if the stored data is not a readable image.
struct PhotoThumbnail: View {
    let photo: AssignmentPhoto

    @State private var image: UIImage?
    @State private var failed = false

    init(photo: AssignmentPhoto) { self.photo = photo }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    Theme.muted
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if failed {
                        VStack(spacing: Theme.Space.xs) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title3)
                            Text("Can't load")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .padding(Theme.Space.xs)
                    } else {
                        ProgressView()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .task(id: photo.persistentModelID) {
                await load()
            }
    }

    @MainActor
    private func load() async {
        let id = photo.persistentModelID
        if let cached = ThumbnailCache.shared.image(for: id) {
            image = cached
            failed = false
            return
        }
        let data = photo.data
        let decoded = await Task.detached(priority: .utility) {
            PhotoProcessor.downsampledImage(from: data, maxPixel: 360)
        }.value
        if Task.isCancelled { return }
        if let decoded {
            ThumbnailCache.shared.store(decoded, for: id)
            image = decoded
            failed = false
        } else {
            failed = true
        }
    }
}

// MARK: - Photos section of the editor

private struct PhotoSelection: Identifiable {
    let id: PersistentIdentifier
}

/// The "Photos" section of the editor: a grid of thumbnails, a multi-select picker, and a
/// full-screen viewer. Works for both a saved assignment and a draft that is not saved yet.
struct PhotoSection: View {
    @Bindable var assignment: Assignment
    let isDraft: Bool
    @Binding var isImporting: Bool

    @Environment(\.modelContext) private var context
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var importing = 0
    @State private var failedImports = 0
    @State private var viewing: PhotoSelection?
    @State private var removal: AssignmentPhoto?

    private let columns = [GridItem(.adaptive(minimum: 88, maximum: 130), spacing: Theme.Space.s)]

    init(assignment: Assignment, isDraft: Bool, isImporting: Binding<Bool>) {
        _assignment = Bindable(wrappedValue: assignment)
        self.isDraft = isDraft
        _isImporting = isImporting
    }

    var body: some View {
        Section {
            if !assignment.photos.isEmpty || importing > 0 {
                grid
            }
            addButton
            if failedImports > 0 {
                Text(failedImports == 1
                     ? "1 photo couldn't be added."
                     : "\(failedImports) photos couldn't be added.")
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }
        } header: {
            Text(assignment.photos.isEmpty ? "Photos" : "Photos (\(assignment.photos.count))")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: Grid

    private var grid: some View {
        let photos = assignment.photos
        return LazyVGrid(columns: columns, spacing: Theme.Space.s) {
            ForEach(photos) { photo in
                ZStack(alignment: .topTrailing) {
                    Button {
                        viewing = PhotoSelection(id: photo.persistentModelID)
                    } label: {
                        PhotoThumbnail(photo: photo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo \(position(of: photo, in: photos)) of \(photos.count)")
                    .accessibilityHint("Opens full size")

                    removeButton(for: photo)
                }
            }
            ForEach(0..<importing, id: \.self) { _ in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ZStack {
                            Theme.muted
                            ProgressView()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    .accessibilityLabel("Adding photo")
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .fullScreenCover(item: $viewing) { selection in
            PhotoViewer(assignment: assignment, startingAt: selection.id) { photo in
                remove(photo)
            }
        }
        .confirmationDialog("Remove this photo?",
                            isPresented: removalPresented,
                            titleVisibility: .visible,
                            presenting: removal) { photo in
            Button("Remove Photo", role: .destructive) {
                remove(photo)
            }
        } message: { _ in
            Text("The photo is deleted from this assignment.")
        }
    }

    private func position(of photo: AssignmentPhoto, in photos: [AssignmentPhoto]) -> Int {
        (photos.firstIndex(where: { $0.persistentModelID == photo.persistentModelID }) ?? 0) + 1
    }

    private var removalPresented: Binding<Bool> {
        Binding(get: { removal != nil },
                set: { newValue in
                    if !newValue { removal = nil }
                })
    }

    private func removeButton(for photo: AssignmentPhoto) -> some View {
        Button {
            removal = photo
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primary)
                .frame(width: 26, height: 26)
                .glassSurface(in: Circle(), interactive: true)
                .frame(width: Theme.Size.tapTarget, height: Theme.Size.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(Theme.Space.xxs)
        .accessibilityLabel("Remove photo")
    }

    // MARK: Adding

    private var addButton: some View {
        PhotosPicker(selection: $pickerItems, matching: .images) {
            Label(assignment.photos.isEmpty ? "Add Photos" : "Add More Photos",
                  systemImage: "photo.badge.plus")
        }
        .onChange(of: pickerItems) { _, items in
            startImport(items)
        }
        .onChange(of: importing) { _, count in
            isImporting = count > 0
        }
    }

    private func startImport(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        // Clear the selection right away so the picker never re-opens with stale selections,
        // and so choosing more photos while these load works.
        pickerItems = []
        importing += items.count
        Task { @MainActor in
            for item in items {
                await importOne(item)
                importing -= 1
            }
        }
    }

    @MainActor
    private func importOne(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            failedImports += 1
            return
        }
        // Decode, scale and compress on a background thread; the main thread stays responsive.
        let prepared = await Task.detached(priority: .userInitiated) {
            PhotoProcessor.prepareForStorage(data)
        }.value
        guard let jpeg = prepared else {
            failedImports += 1
            return
        }
        guard isDraft || assignment.modelContext != nil else { return }
        assignment.photos.append(AssignmentPhoto(data: jpeg))
        if !isDraft { try? context.save() }
    }

    // MARK: Removing

    private func remove(_ photo: AssignmentPhoto) {
        assignment.photos.removeAll { $0.persistentModelID == photo.persistentModelID }
        if photo.modelContext != nil {
            context.delete(photo)
        }
        if !isDraft { try? context.save() }
    }
}

// MARK: - Full-screen viewer

/// Full-screen photos: swipe between them, pinch or double-tap to zoom, remove from here.
struct PhotoViewer: View {
    @Bindable var assignment: Assignment
    let onRemove: (AssignmentPhoto) -> Void

    @State private var selection: PersistentIdentifier
    @State private var confirmRemoval = false
    @Environment(\.dismiss) private var dismiss

    init(assignment: Assignment,
         startingAt id: PersistentIdentifier,
         onRemove: @escaping (AssignmentPhoto) -> Void) {
        _assignment = Bindable(wrappedValue: assignment)
        _selection = State(initialValue: id)
        self.onRemove = onRemove
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(assignment.photos) { photo in
                    ZoomablePhoto(photo: photo)
                        .tag(photo.persistentModelID)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) { controls }
        .confirmationDialog("Remove this photo?",
                            isPresented: $confirmRemoval,
                            titleVisibility: .visible) {
            Button("Remove Photo", role: .destructive) {
                removeCurrent()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var controls: some View {
        let photos = assignment.photos
        let index = photos.firstIndex(where: { $0.persistentModelID == selection }) ?? 0
        return HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: Theme.Size.tapTarget, height: Theme.Size.tapTarget)
                    .glassSurface(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Close")

            Spacer()

            if photos.count > 1 {
                Text("\(index + 1) of \(photos.count)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .padding(.horizontal, Theme.Space.m)
                    .frame(minHeight: Theme.Size.chipHeight)
                    .glassSurface(in: Capsule())
                    .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
            }

            Spacer()

            Button(role: .destructive) {
                confirmRemoval = true
            } label: {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
                    .frame(width: Theme.Size.tapTarget, height: Theme.Size.tapTarget)
                    .glassSurface(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Remove photo")
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
    }

    private func removeCurrent() {
        let photos = assignment.photos
        guard let index = photos.firstIndex(where: { $0.persistentModelID == selection }) else { return }
        let target = photos[index]

        if photos.count == 1 {
            // Closing first lets the viewer finish leaving before its only photo goes away.
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                onRemove(target)
            }
        } else {
            selection = photos[index == photos.count - 1 ? index - 1 : index + 1].persistentModelID
            onRemove(target)
        }
    }
}

/// One photo, loaded at screen size, with pinch-to-zoom, drag-to-pan and double-tap to zoom.
private struct ZoomablePhoto: View {
    let photo: AssignmentPhoto

    @State private var image: UIImage?
    @State private var failed = false
    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maxScale: CGFloat = 5

    init(photo: AssignmentPhoto) { self.photo = photo }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnify)
                    // Panning only claims drags while zoomed in, so swiping between photos
                    // keeps working at normal size.
                    .simultaneousGesture(pan, including: scale > 1 ? .all : .subviews)
                    .onTapGesture(count: 2) { toggleZoom() }
                    .accessibilityLabel("Photo")
                    .accessibilityHint("Double tap to zoom")
            } else if failed {
                VStack(spacing: Theme.Space.s) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("This photo can't be loaded.")
                        .font(.subheadline)
                }
                .foregroundStyle(Color.white.opacity(0.8))
            } else {
                ProgressView()
                    .tint(Color.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: photo.persistentModelID) {
            await load()
        }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(steadyScale * value.magnification, 1), maxScale)
            }
            .onEnded { _ in
                steadyScale = scale
                if scale <= 1.01 { resetZoom() }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: steadyOffset.width + value.translation.width,
                                height: steadyOffset.height + value.translation.height)
            }
            .onEnded { _ in
                steadyOffset = offset
            }
    }

    private func toggleZoom() {
        withMotion(reduceMotion) {
            if scale > 1 {
                resetZoom()
            } else {
                scale = 2.5
                steadyScale = 2.5
            }
        }
    }

    private func resetZoom() {
        scale = 1
        steadyScale = 1
        offset = .zero
        steadyOffset = .zero
    }

    @MainActor
    private func load() async {
        let data = photo.data
        let decoded = await Task.detached(priority: .userInitiated) {
            PhotoProcessor.downsampledImage(from: data, maxPixel: 2200)
        }.value
        if Task.isCancelled { return }
        if let decoded {
            image = decoded
            failed = false
        } else {
            failed = true
        }
    }
}
