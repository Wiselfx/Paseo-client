#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI

/// The project's icon row: automatic or custom, with Photos, Files and Reset buttons. The
/// parent owns the pickers' state, because it also runs the upload.
struct ProjectIconGroup: View {
    let icons: ProjectIconStore
    let projectId: String
    @Binding var hasCustomIcon: Bool
    @Binding var photoItem: PhotosPickerItem?
    @Binding var pickingFile: Bool
    /// Why the last picked photo or file could not be read; the store's own `error` is separate.
    let loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionLabel(title: "Icon", tucksIntoGroup: false)
            RowGroup {
                HStack(spacing: Space.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Icon")
                            .font(.paseo(.body))
                            .foregroundStyle(Palette.ink)
                        Text(hasCustomIcon ? "Custom" : "Automatic")
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    Spacer(minLength: Space.sm)
                    if icons.isSaving {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(.horizontal, Space.lg)
                .frame(minHeight: 51)
                RowDivider()
                HStack(spacing: Space.sm) {
                    // Built here on the main actor: PhotosPicker's label closure is nonisolated.
                    let photosLabel = ProjectChip {
                        Label("Photos", systemImage: "photo")
                            .font(.paseo(.footnote, weight: .medium))
                            .foregroundStyle(Palette.ink)
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        photosLabel
                    }
                    .buttonStyle(.plain)
                    .disabled(!icons.supportsCustomIcon)
                    .opacity(icons.supportsCustomIcon ? 1 : 0.45)
                    .accessibilityLabel("Choose a photo for the project icon")
                    Button {
                        pickingFile = true
                    } label: {
                        ProjectChip {
                            Label("Files", systemImage: "doc")
                                .font(.paseo(.footnote, weight: .medium))
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!icons.supportsCustomIcon)
                    .opacity(icons.supportsCustomIcon ? 1 : 0.45)
                    .accessibilityLabel("Choose a file for the project icon")
                    if hasCustomIcon {
                        Button {
                            Task {
                                let ok = await icons.reset(projectId: projectId)
                                if ok {
                                    hasCustomIcon = false
                                    Haptics.success()
                                } else {
                                    Haptics.failure()
                                }
                            }
                        } label: {
                            ProjectChip {
                                Text("Reset")
                                    .font(.paseo(.footnote, weight: .medium))
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!icons.supportsCustomIcon)
                        .accessibilityLabel("Reset the project icon to automatic")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.lg)
                .frame(minHeight: 51)
                if !icons.supportsCustomIcon {
                    Text("This host can't set project icons.")
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.horizontal, Space.lg)
                        .padding(.bottom, Space.md)
                }
                if let error = icons.error {
                    Text(error)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                        .padding(.horizontal, Space.lg)
                        .padding(.bottom, Space.md)
                }
                if let loadError {
                    Text(loadError)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                        .padding(.horizontal, Space.lg)
                        .padding(.bottom, Space.md)
                }
            }
        }
    }
}
#endif
