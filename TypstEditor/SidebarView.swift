import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @State private var expandedFolders: Set<URL> = []

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────
            HStack(spacing: 6) {
                if let root = state.projectURL {
                    Text(root.lastPathComponent)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("no project")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
                // New file
                Button(action: { state.newFile() }) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("New .typ file")
                .disabled(state.projectURL == nil)

                // Refresh
                Button(action: { state.refreshTree() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Refresh")
                .disabled(state.projectURL == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // ── File tree ─────────────────────────────────────────
            if state.projectURL == nil {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("Open a project folder\nto get started")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Open Project…") { state.openProject() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.fileTree.isEmpty {
                Text("Empty folder")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(state.fileTree) { node in
                            FileRowView(node: node, depth: 0, expandedFolders: $expandedFolders)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - File Row

struct FileRowView: View {
    let node: FileNode
    let depth: Int
    @Binding var expandedFolders: Set<URL>
    @EnvironmentObject var state: AppState

    private var isExpanded: Bool { expandedFolders.contains(node.url) }
    private var isActive: Bool { state.activeURL == node.url }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                // Indent
                Spacer().frame(width: CGFloat(depth) * 14 + 8)

                // Chevron for folders
                if node.isFolder {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                } else {
                    Spacer().frame(width: 12)
                }

                // Icon
                Image(systemName: iconName(for: node))
                    .font(.system(size: 12))
                    .foregroundColor(iconColor(for: node))

                // Name
                Text(node.name)
                    .font(.system(size: 12))
                    .foregroundColor(isActive ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.vertical, 3)
            .background(isActive ? Color.accentColor : Color.clear)
            .cornerRadius(4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isFolder {
                    if isExpanded { expandedFolders.remove(node.url) }
                    else          { expandedFolders.insert(node.url) }
                } else {
                    state.open(node: node)
                }
            }

            // Children
            if node.isFolder && isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileRowView(node: child, depth: depth + 1, expandedFolders: $expandedFolders)
                }
            }
        }
    }

    private func iconName(for node: FileNode) -> String {
        if node.isFolder { return isExpanded ? "folder.open" : "folder" }
        switch node.url.pathExtension.lowercased() {
        case "typ":          return "doc.text"
        case "pdf":          return "doc.richtext"
        case "png","jpg","jpeg","gif","svg","webp": return "photo"
        case "bib":          return "books.vertical"
        default:             return "doc"
        }
    }

    private func iconColor(for node: FileNode) -> Color {
        if isActive { return .white }
        if node.isFolder { return .accentColor }
        switch node.url.pathExtension.lowercased() {
        case "typ":  return .primary
        case "pdf":  return .red
        case "png","jpg","jpeg","gif","svg","webp": return .purple
        case "bib":  return .orange
        default:     return .secondary
        }
    }
}
