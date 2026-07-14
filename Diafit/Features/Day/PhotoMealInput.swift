import PhotosUI
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// A privacy-first intake surface. The selected image is normalized and
/// metadata-stripped before it leaves this view; this local build keeps it in
/// memory for the draft only and does not upload it.
struct PhotoMealInput: View {
    @Environment(\.dismiss) private var dismiss
    let onContinue: (PreparedFoodImage, String) -> Void

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var preparedImage: PreparedFoodImage?
    @State private var previewImage: UIImage?
    @State private var dishDescription = ""
    @State private var errorMessage: String?
    @State private var showsCamera = false

    private let preparation = AppleImagePreparationService()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("PHOTO NOTE")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.3)
                            .foregroundStyle(Color.quietInk)
                        Text("Start with what’s on your plate.")
                            .font(DiafitType.display)
                            .foregroundStyle(Color.ink)
                        Text("You’ll review every food, serving, and estimate before anything is added to today.")
                            .font(DiafitType.body)
                            .foregroundStyle(Color.quietInk)
                            .lineSpacing(3)
                    }

                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 248)
                            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                Text("ORIGINAL PHOTO · DRAFT ONLY")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .tracking(0.9)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(.black.opacity(0.4), in: Capsule())
                                    .padding(13)
                            }
                    } else {
                        PhotoDropTarget()
                    }

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                            Label("Choose photo", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(QuietActionStyle())
                        .accessibilityLabel("Choose meal photo")

                        Button { showsCamera = true } label: {
                            Label("Camera", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(QuietActionStyle())
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        .accessibilityLabel("Take meal photo")
                    }

                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("UITestUseFixturePhoto") {
                        Button("Use review fixture") { loadReviewFixture() }
                            .font(DiafitType.caption)
                            .foregroundStyle(Color.quietInk)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 5)
                            .accessibilityHint("Development-only test fixture")
                    }
                    #endif

                    if preparedImage != nil {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("What’s the main dish?")
                                .font(DiafitType.title)
                                .foregroundStyle(Color.ink)
                            Text("A short description helps when photo recognition is unavailable. Try “dosa with sambar and coconut chutney.”")
                                .font(DiafitType.caption)
                                .foregroundStyle(Color.quietInk)
                                .lineSpacing(2)
                            TextField("Describe what you see", text: $dishDescription, axis: .vertical)
                                .font(DiafitType.body)
                                .lineLimit(2...4)
                                .padding(14)
                                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.rule.opacity(0.7), lineWidth: 0.8))
                        }
                    }

                    PrivacyNote()

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(DiafitType.caption)
                            .foregroundStyle(Color.coral)
                    }

                    Button(action: continueToReview) {
                        HStack {
                            Text("Create a review")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.paper)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(Color.ink, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    }
                    .buttonStyle(PressableStyle(pressedScale: 0.98))
                    .disabled(preparedImage == nil || dishDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(preparedImage == nil || dishDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.42 : 1)
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.paper)
            .navigationTitle("Add a meal photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
            .sheet(isPresented: $showsCamera) {
                CameraCapture { image in
                    prepare(image?.jpegData(compressionQuality: 0.94))
                }
                .ignoresSafeArea()
            }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "That photo could not be read. Choose another image."
                return
            }
            prepare(data)
        } catch {
            errorMessage = "That photo could not be read. Choose another image."
        }
    }

    private func prepare(_ data: Data?) {
        guard let data else {
            errorMessage = "That photo could not be prepared."
            return
        }
        do {
            let image = try preparation.prepare(imageData: data)
            preparedImage = image
            previewImage = UIImage(data: image.data)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func continueToReview() {
        guard let preparedImage else { return }
        onContinue(preparedImage, dishDescription.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }

    #if DEBUG
    private func loadReviewFixture() {
        guard let url = Bundle.main.url(forResource: "bowl", withExtension: "png"),
              let data = try? Data(contentsOf: url) else {
            errorMessage = "The review fixture is unavailable."
            return
        }
        dishDescription = "Dosa with sambar and coconut chutney"
        prepare(data)
    }
    #endif
}

struct AppleImagePreparationService: ImageCompressionService {
    private let maxInputBytes = 20 * 1_024 * 1_024
    private let maxUploadBytes = 2 * 1_024 * 1_024
    private let maxPixelDimension: CGFloat = 2_048

    func prepare(imageData: Data) throws -> PreparedFoodImage {
        guard imageData.count <= maxInputBytes else { throw FoodAnalysisError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let type = CGImageSourceGetType(source),
              let typeIdentifier = UTType(type as String),
              [UTType.jpeg, UTType.png, UTType.heic, UTType.heif].contains(typeIdentifier),
              let uiImage = UIImage(data: imageData),
              uiImage.size.width > 0, uiImage.size.height > 0 else {
            throw FoodAnalysisError.unsupportedImage
        }

        let scale = min(1, maxPixelDimension / max(uiImage.size.width, uiImage.size.height))
        let targetSize = CGSize(width: floor(uiImage.size.width * scale), height: floor(uiImage.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let normalized = renderer.image { _ in
            uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        // A fresh JPEG representation deliberately drops EXIF, including location metadata.
        var quality: CGFloat = 0.86
        var data = normalized.jpegData(compressionQuality: quality) ?? Data()
        while data.count > maxUploadBytes && quality > 0.46 {
            quality -= 0.12
            data = normalized.jpegData(compressionQuality: quality) ?? data
        }
        guard !data.isEmpty, data.count <= maxUploadBytes else { throw FoodAnalysisError.imageTooLarge }

        return PreparedFoodImage(
            data: data,
            mimeType: "image/jpeg",
            pixelWidth: Int(targetSize.width),
            pixelHeight: Int(targetSize.height),
            imageReference: .transient()
        )
    }
}

private struct PhotoDropTarget: View {
    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: "camera.macro")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.ink)
            Text("One plate, many components")
                .font(DiafitType.title)
                .foregroundStyle(Color.ink)
            Text("Rice, dal, roti, sabzi, and sides stay separate so you can correct each one.")
                .font(DiafitType.caption)
                .foregroundStyle(Color.quietInk)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .background(Color.mist.opacity(0.52), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.rule.opacity(0.72), style: StrokeStyle(lineWidth: 1, dash: [5, 6])))
    }
}

private struct PrivacyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.ink)
                .frame(width: 28, height: 28)
                .background(Color.lime.opacity(0.38), in: Circle())
            Text("This build keeps the prepared photo on this device for this review only. It removes location metadata and does not upload or retain the original. A production analysis service will ask before secure processing and explain retention.")
                .font(DiafitType.caption)
                .foregroundStyle(Color.quietInk)
                .lineSpacing(2)
        }
        .padding(13)
        .background(Color.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct QuietActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DiafitType.caption)
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.white.opacity(configuration.isPressed ? 0.45 : 0.74), in: Capsule())
            .overlay(Capsule().stroke(Color.rule.opacity(0.72), lineWidth: 0.8))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct CameraCapture: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCapture
        init(parent: CameraCapture) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.completion(nil)
            parent.dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.completion(info[.originalImage] as? UIImage)
            parent.dismiss()
        }
    }
}
