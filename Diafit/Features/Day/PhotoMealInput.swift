import PhotosUI
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// A privacy-first, single-action intake surface. Choosing or taking a photo
/// immediately prepares it and starts analysis; a description is never a
/// prerequisite for the normal path.
struct PhotoMealInput: View {
    @Environment(\.dismiss) private var dismiss
    let onContinue: (PreparedFoodImage, String) -> Void

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var showsCamera = false
    @State private var isPreparing = false

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
                        Text("Choose a meal photo.")
                            .font(DiafitType.display)
                            .foregroundStyle(Color.ink)
                        Text("Diafit will identify visible foods, calculate an editable nutrition estimate, and take you straight to review.")
                            .font(DiafitType.body)
                            .foregroundStyle(Color.quietInk)
                            .lineSpacing(3)
                    }

                    PhotoDropTarget()

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                            Label("Choose & analyse", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(QuietActionStyle())
                        .disabled(isPreparing)
                        .accessibilityLabel("Choose meal photo")

                        Button { showsCamera = true } label: {
                            Label("Camera", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(QuietActionStyle())
                        .disabled(isPreparing || !UIImagePickerController.isSourceTypeAvailable(.camera))
                        .accessibilityLabel("Take meal photo")
                    }

                    if isPreparing {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(Color.ink)
                            Text("Preparing your private photo…")
                                .font(DiafitType.caption)
                                .foregroundStyle(Color.quietInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Preparing meal photo for analysis")
                    }

                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("UITestUseFixturePhoto") {
                        VStack(spacing: 7) {
                            Button("Use review fixture") { loadReviewFixture() }
                            Button("Use correction fixture") { loadCorrectionFixture() }
                        }
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.quietInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 5)
                        .accessibilityHint("Development-only test fixtures")
                    }
                    #endif

                    PrivacyNote()

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(DiafitType.caption)
                            .foregroundStyle(Color.coral)
                    }

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
        isPreparing = true
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "That photo could not be read. Choose another image."
                isPreparing = false
                return
            }
            prepare(data)
        } catch {
            errorMessage = "That photo could not be read. Choose another image."
            isPreparing = false
        }
    }

    private func prepare(_ data: Data?, hint: String = "") {
        isPreparing = true
        guard let data else {
            errorMessage = "That photo could not be prepared."
            isPreparing = false
            return
        }
        do {
            let image = try preparation.prepare(imageData: data)
            errorMessage = nil
            onContinue(image, hint)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isPreparing = false
        }
    }

    #if DEBUG
    private func loadReviewFixture() {
        guard let url = Bundle.main.url(forResource: "bowl", withExtension: "png"),
              let data = try? Data(contentsOf: url) else {
            errorMessage = "The review fixture is unavailable."
            return
        }
        prepare(data, hint: "Dosa with sambar and coconut chutney")
    }

    private func loadCorrectionFixture() {
        guard let url = Bundle.main.url(forResource: "bowl", withExtension: "png"),
              let data = try? Data(contentsOf: url) else {
            errorMessage = "The correction fixture is unavailable."
            return
        }
        prepare(data, hint: "unrecognised plate fixture")
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
            Text("Choose one photo. Visible foods stay separate so you can correct servings before saving.")
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
            Text("Analysis starts on this device. If local recognition is uncertain and Live Recognition is configured, a metadata-stripped copy is sent securely to the configured AI provider. The original stays in this review, and nothing is logged until you confirm.")
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
