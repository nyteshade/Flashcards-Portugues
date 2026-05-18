import MLXModelKit

extension ModelVariant {
    /// All EuroLLM variants the app knows about — the single source of
    /// truth for Settings UI, autoLoad routing, and the translator.
    static let euroLLMAll: [ModelVariant] = [
        ModelVariant(
            id: "eurollm-1.7b-instruct-4bit",
            displayName: "EuroLLM 1.7B Instruct (4-bit)",
            huggingFaceRepo: "dreamer1cc/EuroLLM-1.7B-Instruct-4bit",
            quant: .fourBit,
            parameterScale: .b1_7,
            estimatedBytes: Int(1.5 * 1024 * 1024 * 1024),
            sizeOnDiskHint: "~1.0 GB"
        ),
        ModelVariant(
            id: "eurollm-1.7b-instruct-bf16",
            displayName: "EuroLLM 1.7B Instruct (bf16)",
            huggingFaceRepo: "utter-project/EuroLLM-1.7B-Instruct",
            quant: .bfloat16,
            parameterScale: .b1_7,
            estimatedBytes: Int(4.0 * 1024 * 1024 * 1024),
            sizeOnDiskHint: "~3.4 GB"
        ),
        ModelVariant(
            id: "eurollm-9b-instruct-mlx-4bit",
            displayName: "EuroLLM 9B Instruct (4-bit)",
            huggingFaceRepo: "stelterlab/EuroLLM-9B-Instruct-MLX-4bit",
            quant: .fourBit,
            parameterScale: .b9,
            estimatedBytes: 6 * 1024 * 1024 * 1024,
            sizeOnDiskHint: "~5.4 GB"
        ),
        ModelVariant(
            id: "eurollm-22b-instruct-2512-mlx-4bit",
            displayName: "EuroLLM 22B Instruct (4-bit)",
            huggingFaceRepo: "mlx-community/EuroLLM-22B-Instruct-2512-mlx-4bit",
            quant: .fourBit,
            parameterScale: .b22,
            estimatedBytes: 14 * 1024 * 1024 * 1024,
            sizeOnDiskHint: "~13 GB"
        ),
    ]

    /// Stable UserDefaults / `@AppStorage` key for the user's chosen
    /// default variant. Value is either `"auto"` or a `ModelVariant.id`.
    static let activeVariantDefaultsKey = "eurollm_active_variant"
}
