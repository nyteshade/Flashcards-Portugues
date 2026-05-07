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
        to toLang: String = "en-GB",
        completion: @escaping (String?) -> Void
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(nil)
            return
        }
        
        let urlString = "https://api.mymemory.translated.net/get?q=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&langpair=\(fromLang)|\(toLang)"
        
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        Logger.log("Translation URL: \(urlString)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            Logger.log("Translation data: \(String(data: data, encoding: .utf8) ?? "no data")")

            do {
                let result = try JSONDecoder().decode(TranslationResponse.self, from: data)
                DispatchQueue.main.async {
                    let decodedText = result.responseData.translatedText.removingPercentEncoding ?? result.responseData.translatedText
                    completion(decodedText)
                }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }
}
