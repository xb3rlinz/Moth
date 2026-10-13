import SwiftUI

// MARK: - Section titles

/// Heading for a group of rows: a quiet semibold title with an optional count.
struct SectionTitle: View {
    let title: String
    let count: Int?
    let tone: DueInfo.Tone

    init(_ title: String, count: Int? = nil, tone: DueInfo.Tone = .normal) {
        self.title = title
        self.count = count
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(title)
                .font(.mothSectionTitle)
                .foregroundStyle(tone == .overdue ? Theme.danger : Color.primary)
            if let count {
                Text("\(count)")
                    .font(.mothSectionTitle)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Styles a `SectionTitle` that is placed as the first row of a section: no separator, no
    /// background, and the breathing room a heading needs. Titles are ordinary rows rather
    /// than pinned section headers so they never become translucent bars over the rows
    /// scrolling beneath them, and so their look is fully controlled by the design tokens.
    func sectionHeaderRow(topSpacing: CGFloat = Theme.Space.l) -> some View {
        listRowInsets(EdgeInsets(top: topSpacing,
                                 leading: Theme.Size.rowInset,
                                 bottom: Theme.Space.xs,
                                 trailing: Theme.Size.rowInset))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// MARK: - Empty states

/// A calm, centred explanation with one clear next step.
struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(title: String,
         message: String,
         systemImage: String,
         actionTitle: String? = nil,
         action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(MothButtonStyle(kind: .prominent))
            }
        }
    }
}

// MARK: - Meta text

/// One piece of the secondary line under an assignment title ("English", "Due tomorrow"...).
struct MetaSegment: Hashable {
    let text: String
    let tone: DueInfo.Tone

    init(_ text: String, tone: DueInfo.Tone = .normal) {
        self.text = text
        self.tone = tone
    }
}

/// Joins segments with a centred dot into a single wrapping line. Overdue pieces are red and
/// "today" pieces use the accent colour; the rest inherit the surrounding style.
func metaText(_ segments: [MetaSegment]) -> AttributedString {
    var result = AttributedString()
    for (index, segment) in segments.enumerated() {
        if index > 0 {
            result.append(AttributedString(" · "))
        }
        var piece = AttributedString(segment.text)
        switch segment.tone {
        case .overdue:
            piece[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Theme.danger
        case .today:
            piece[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Theme.accent
        case .normal:
            break
        }
        result.append(piece)
    }
    return result
}

// MARK: - Chips

/// The look of a filter chip. Wrap it in a `Menu` or `Button`; it draws no tap behaviour itself.
struct FilterChip: View {
    let title: String
    let systemImage: String?
    let isActive: Bool
    let showsChevron: Bool

    init(_ title: String, systemImage: String? = nil, isActive: Bool = false, showsChevron: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.isActive = isActive
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
            }
            Text(title)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .opacity(0.7)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isActive ? Theme.accent : Color.primary)
        .padding(.horizontal, Theme.Space.m)
        .frame(minHeight: Theme.Size.chipHeight)
        .glassSurface(in: Capsule(),
                      tint: isActive ? Theme.accent : nil,
                      interactive: true,
                      fallback: .fill)
        // Visually 36pt tall, but the tappable area reaches the recommended 44pt.
        .padding(.vertical, (Theme.Size.tapTarget - Theme.Size.chipHeight) / 2)
        .contentShape(Rectangle())
    }
}

/// A horizontally scrolling row of tappable suggestions under a text field.
struct SuggestionChips: View {
    let items: [String]
    let hint: String
    let select: (String) -> Void

    init(items: [String], hint: String, select: @escaping (String) -> Void) {
        self.items = items
        self.hint = hint
        self.select = select
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                ForEach(items, id: \.self) { item in
                    Button {
                        select(item)
                    } label: {
                        Text(item)
                            .lineLimit(1)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, Theme.Space.m)
                            .frame(minHeight: 32)
                            .background(Theme.muted, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(hint)
                }
            }
            .padding(.vertical, Theme.Space.xxs)
        }
    }
}

// MARK: - Small badges

/// "📷 2": how many photos an assignment carries.
struct PhotoCountBadge: View {
    let count: Int

    init(count: Int) { self.count = count }

    var body: some View {
        Label("\(count)", systemImage: "photo")
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
            .accessibilityHidden(true)
    }
}
