import PhotosUI
import SwiftUI
import UIKit
import Vision
import VisionKit

struct PackagedFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    let repository: any PackagedFoodRepository
    let onReview: (MealAnalysisDraft) -> Void

    @State private var barcode = ""
    @State private var name = ""
    @State private var brand = ""
    @State private var flavour = ""
    @State private var grams = ""
    @State private var calories = ""
    @State private var carbs = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var source = "Package label"
    @State private var loadedRecord: PackagedFoodRecord?
    @State private var labelExpanded = true
    @State private var labelPhoto: PhotosPickerItem?
    @State private var labelText: String?
    @State private var message: String?
    @State private var scanning = false
    @State private var takingPhoto = false
    @State private var busy = false
    @State private var savedProducts: [PackagedFoodRecord] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                        Button("Scan barcode", systemImage: "barcode.viewfinder") { scanning = true }
                    }
                    TextField("Barcode (optional)", text: $barcode)
                        .keyboardType(.numberPad)
                    Button("Look up barcode") { Task { await lookUp() } }
                        .disabled(normalizedBarcode == nil)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lookup checks saved products first and sends unmatched barcodes to Open Food Facts.")
                        Link("Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org/")!)
                    }
                }

                if !savedProducts.isEmpty {
                    Section("Saved products") {
                        Menu("Choose a saved product") {
                            ForEach(savedProducts) { record in
                                Button(productTitle(record)) {
                                    barcode = record.barcode ?? ""
                                    fill(record)
                                    message = "Check the product and portion before continuing."
                                }
                            }
                        }
                    }
                }

                Section("Product") {
                    TextField("Product name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                    TextField("Flavour (optional)", text: $flavour)
                    field("Portion to log (g)", $grams)
                }

                Section {
                    field("Energy (kcal)", $calories)
                    field("Carbohydrates (g)", $carbs)
                    field("Protein (g)", $protein)
                    field("Fat (g)", $fat)
                    PhotosPicker(selection: $labelPhoto, matching: .images) {
                        Label("Read a label photo", systemImage: "photo")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Photograph label", systemImage: "camera") { takingPhoto = true }
                    }
                    if let labelText {
                        DisclosureGroup("Text read from label", isExpanded: $labelExpanded) {
                            Text(labelText).font(.footnote).textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("Nutrition per 100 g")
                } footer: {
                    Text("Check the per-100 g column on the package. Label photos are read on your iPhone.")
                }

                if busy { ProgressView() }
                if let message { Text(message).font(.footnote) }
            }
            .disabled(busy)
            .navigationTitle("Packaged food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & review") { Task { await save() } }.disabled(busy)
                }
            }
        }
        .interactiveDismissDisabled(busy)
        .task {
            if let exporting = repository as? any PackagedFoodDataExporting {
                savedProducts = await exporting.allRecords().sorted { $0.productName < $1.productName }
            }
        }
        .sheet(isPresented: $scanning) {
            BarcodeScanner { code in
                scanning = false
                guard let code else {
                    message = "Camera scanning is unavailable. Enter the barcode manually."
                    return
                }
                barcode = code
                Task { await lookUp() }
            }
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button("Close") { scanning = false }
                    .padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            }
        }
        .fullScreenCover(isPresented: $takingPhoto) {
            CameraCapture { image in
                guard let data = image?.jpegData(compressionQuality: 0.85) else { return }
                Task { await readLabel(data) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: labelPhoto) { _, photo in
            guard let photo else { return }
            Task {
                guard let data = try? await photo.loadTransferable(type: Data.self),
                      labelPhoto == photo else { return }
                await readLabel(data)
            }
        }
        .onChange(of: barcode) { _, _ in
            if let code = loadedRecord?.barcode, normalizedBarcode != code {
                name = ""
                brand = ""
                flavour = ""
                grams = ""
                calories = ""
                carbs = ""
                protein = ""
                fat = ""
                source = "Package label"
                loadedRecord = nil
            }
        }
    }

    private var normalizedBarcode: String? {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard [8, 12, 13, 14].contains(code.count),
              code.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        // AVFoundation can report UPC-A as EAN-13 with a leading zero.
        return code.count == 13 && code.first == "0" ? String(code.dropFirst()) : code
    }

    private func field(_ title: String, _ value: Binding<String>) -> some View {
        TextField(title, text: value).keyboardType(.decimalPad)
    }

    private func number(_ value: String) -> Double? {
        try? Double(value.trimmingCharacters(in: .whitespacesAndNewlines), format: .number)
    }

    private func productTitle(_ record: PackagedFoodRecord) -> String {
        [record.brand, record.productName, record.flavour ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func fill(_ record: PackagedFoodRecord) {
        name = record.productName
        brand = record.brand
        flavour = record.flavour ?? ""
        source = record.source
        loadedRecord = record
        grams = record.servingGrams > 0 ? record.servingGrams.formatted(.number.grouping(.never)) : ""
        let per100 = record.nutritionPer100Grams ?? record.nutritionPerServing.scaled(by: 100 / record.servingGrams)
        func input(_ value: Double?) -> String {
            value?.formatted(.number.grouping(.never).precision(.fractionLength(0...4))) ?? ""
        }
        calories = input(per100.caloriesKcal)
        carbs = input(per100.carbohydrateGrams)
        protein = input(per100.proteinGrams)
        fat = input(per100.fatGrams)
    }

    @MainActor
    private func lookUp() async {
        guard !busy, let code = normalizedBarcode else { return }
        busy = true
        message = nil
        defer { busy = false }
        if let existing = await repository.find(brand: nil, productName: nil, barcode: code, flavour: nil) {
            fill(existing)
            message = "Saved product found. Check its portion before continuing."
            return
        }
        do {
            guard let record = try await OpenFoodFactsLookup.product(for: code) else {
                message = "No match found. Enter the values from the package or read a label photo."
                return
            }
            fill(record)
            message = "Check these Open Food Facts values against the package. Enter your portion in grams."
        } catch {
            message = "Lookup is unavailable. You can still enter the package values."
        }
    }

    @MainActor
    private func readLabel(_ data: Data) async {
        guard !busy else { return }
        busy = true
        labelText = nil
        labelExpanded = true
        defer { busy = false }
        do {
            let text = try await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(data: data).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }.value
            labelText = text.isEmpty ? nil : text
            message = text.isEmpty ? "No label text was detected." : "Use the text below the photo controls to fill in the per-100 g values."
        } catch {
            message = "Couldn’t read the label. Try a clearer photo or enter the values directly."
        }
    }

    @MainActor
    private func save() async {
        guard !busy else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = normalizedBarcode
        guard barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || code != nil else {
            message = "Enter an 8-, 12-, 13- or 14-digit barcode, or leave it blank."
            return
        }
        guard !name.isEmpty, let portion = number(grams), (0.1...5000).contains(portion),
              let kcal = number(calories), let carbs = number(carbs),
              let protein = number(protein), let fat = number(fat) else {
            message = "Enter the product name, portion in grams and all four nutrition values."
            return
        }
        let nutrition = NutritionValues(caloriesKcal: kcal, proteinGrams: protein, carbohydrateGrams: carbs, fatGrams: fat)
        let validator = DefaultNutritionValidationService()
        let values = nutrition.scaled(by: portion / 100)
        let report = validator.validate(rawValues: values, quantity: portion, servingUnit: .grams, estimatedWeightGrams: portion)
        guard [kcal, carbs, protein, fat].allSatisfy({ $0.isFinite && $0 >= 0 }),
              kcal <= 1000, carbs + protein + fat <= 103, report.isApproved else {
            message = "Check the calories and grams in the per-100 g column."
            return
        }

        busy = true
        defer { busy = false }
        let brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let flavour = flavour.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingRecord = loadedRecord.flatMap { previous in
            previous.barcode == code && previous.brand == brand && previous.productName == name
                && (previous.flavour ?? "") == flavour ? previous : nil
        }
        let sameBarcodeRecord = code != nil && loadedRecord?.barcode == code ? loadedRecord : nil
        let id = matchingRecord?.id ?? sameBarcodeRecord?.id ?? code.map { "barcode:\($0)" }
            ?? "label:" + [brand, name, flavour].joined(separator: "|").lowercased()
        let record = PackagedFoodRecord(
            id: id, brand: brand, productName: name, barcode: code, flavour: flavour.isEmpty ? nil : flavour,
            gramsPerScoop: matchingRecord?.gramsPerScoop, servingGrams: portion, nutritionPerServing: values,
            nutritionPer100Grams: nutrition, source: source, sourceVersion: matchingRecord?.sourceVersion, userConfirmed: true
        )
        await repository.save(record)
        if let exporting = repository as? any PackagedFoodDataExporting,
           !(await exporting.allRecords()).contains(record) {
            message = "This product couldn’t be saved. Check device storage and try again."
            return
        }
        let provenance = NutritionProvenance(
            kind: .packagedLabel, dataSource: source, dataVersion: record.sourceVersion, confidence: .high, sourceRecordID: id
        )
        let item = DetectedFoodItem(
            id: UUID(), canonicalFoodId: id, displayName: productTitle(record), category: .unknown,
            confidence: .high, alternatives: [], quantity: portion, servingUnit: .grams,
            estimatedWeightGrams: portion, visibleIngredients: [], inferredIngredients: [], possibleIngredients: [],
            nutrition: values, glycaemicInformation: .unavailable, assumptions: [], warnings: [],
            nutritionProvenance: provenance, rawNutrition: values, nutritionValidation: report
        )
        let result = MealAnalysisResult(
            analysisId: UUID(), imageReference: .transient(), imageType: .noImage, detectedItems: [item],
            mealTotals: values, overallConfidence: .high, assumptions: [], clarificationQuestions: [],
            warnings: [], createdAt: .now, nutritionProvenance: provenance, nutritionValidation: report
        )
        onReview(MealAnalysisDraft(result: result))
        dismiss()
    }
}

private struct BarcodeScanner: UIViewControllerRepresentable {
    let onScan: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce, .itf14])],
            qualityLevel: .balanced, recognizesMultipleItems: false, isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        do {
            try scanner.startScanning()
        } catch {
            Task { @MainActor in context.coordinator.finish(nil, scanner: scanner) }
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String?) -> Void
        private var finished = false

        init(onScan: @escaping (String?) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    finish(value, scanner: scanner)
                    return
                }
            }
        }

        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            finish(nil, scanner: scanner)
        }

        func finish(_ code: String?, scanner: DataScannerViewController) {
            guard !finished else { return }
            finished = true
            scanner.stopScanning()
            onScan(code)
        }
    }
}

private enum OpenFoodFactsLookup {
    private struct Response: Decodable {
        let product: Product?
    }

    private struct Product: Decodable {
        let product_name: String?
        let brands: String?
        let product_quantity_unit: String?
        let serving_quantity_unit: String?
        let serving_quantity: Double?
        let nutriments: [String: Double]?

        enum CodingKeys: String, CodingKey {
            case product_name, brands, product_quantity_unit, serving_quantity_unit, serving_quantity, nutriments
        }

        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            product_name = try? fields.decode(String.self, forKey: .product_name)
            brands = try? fields.decode(String.self, forKey: .brands)
            product_quantity_unit = try? fields.decode(String.self, forKey: .product_quantity_unit)
            serving_quantity_unit = try? fields.decode(String.self, forKey: .serving_quantity_unit)
            serving_quantity = (try? fields.decode(Double.self, forKey: .serving_quantity))
                ?? (try? fields.decode(String.self, forKey: .serving_quantity)).flatMap { Double($0) }
            let nutrientFields = try? fields.nestedContainer(keyedBy: NutrientKey.self, forKey: .nutriments)
            nutriments = nutrientFields.map { nutrients in
                Dictionary(uniqueKeysWithValues: nutrients.allKeys.compactMap { key in
                    let value = (try? nutrients.decode(Double.self, forKey: key))
                        ?? (try? nutrients.decode(String.self, forKey: key)).flatMap { Double($0) }
                    return value.map { (key.stringValue, $0) }
                })
            }
        }
    }

    private struct NutrientKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    static func product(for code: String) async throws -> PackagedFoodRecord? {
        let base = URL(string: "https://world.openfoodfacts.org/api/v3/product/")!
        let url = base.appending(path: "\(code).json")
            .appending(queryItems: [URLQueryItem(
                name: "fields",
                value: "product_name,brands,product_quantity_unit,serving_quantity_unit,serving_quantity,nutriments"
            )])
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Diafit/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard let product = try JSONDecoder().decode(Response.self, from: data).product,
              let name = product.product_name, !name.isEmpty else { return nil }
        let units = [product.product_quantity_unit, product.serving_quantity_unit].compactMap { $0?.lowercased() }
        let isLiquid = units.contains { ["ml", "cl", "dl", "l", "fl oz"].contains($0) }
        let nutrients = isLiquid ? nil : product.nutriments
        let values = NutritionValues(
            caloriesKcal: nutrients?["energy-kcal_100g"], proteinGrams: nutrients?["proteins_100g"],
            carbohydrateGrams: nutrients?["carbohydrates_100g"], fatGrams: nutrients?["fat_100g"]
        )
        let portion = product.serving_quantity_unit == "g" ? product.serving_quantity ?? 0 : 0
        return PackagedFoodRecord(
            id: "barcode:\(code)", brand: product.brands ?? "", productName: name, barcode: code,
            servingGrams: portion, nutritionPerServing: values.scaled(by: portion / 100),
            nutritionPer100Grams: values, source: "Open Food Facts · user-reviewed",
            sourceVersion: "v3", userConfirmed: false
        )
    }
}
