import Foundation

struct TranslationResponse: Codable {
  let responseData: ResponseData
  
  struct ResponseData: Codable {
    let translatedText: String
  }
}

enum TranslationService {
  static func translate(
    text: String,
    from fromLang: String = "pt-PT",
    to toLang: String = "en-GB"
  ) async -> String? {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    
    let urlString = "https://api.mymemory.translated.net/get?q=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&langpair=\(fromLang)|\(toLang)"
    
    guard let url = URL(string: urlString) else {
      return nil
    }
    
    Logger.log("Translation URL: \(urlString)")
    
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      Logger.log("Translation data: \(String(data: data, encoding: .utf8) ?? "no data")")
      let result = try JSONDecoder().decode(TranslationResponse.self, from: data)
      return result.responseData.translatedText.removingPercentEncoding ?? result.responseData.translatedText
    }
    catch {
      return nil
    }
  }
}
