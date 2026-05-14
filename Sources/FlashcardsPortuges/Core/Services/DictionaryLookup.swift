import Foundation

// MARK: - Dictionary Data Structures
struct DictionaryData: Codable {
  let languageCode: String
  let languageName: String
  let languageNativeName: String
  let words: [WordEntry]
}

struct WordEntry: Codable {
  let rank: Int
  let targetWord: String
  let englishWord: String
}

enum DictionaryLookup {
  
  private static let dictionaryURL = URL(string: "https://raw.githubusercontent.com/SMenigat/thousand-most-common-words/master/words/pt.json")!
  
  private static var dictionaryFileURL: URL {
    PathProvider.appSupportDirectory.appendingPathComponent("pt-en-dictionary.json")
  }
  
  nonisolated(unsafe) private static var ptEnDict: [String: String]?
  nonisolated(unsafe) private static var enPtDict: [String: String]?
  
  static func loadDictionary(completion: @escaping (Bool) -> Void) {
    Logger.log("Attempting to load dictionary from: \(dictionaryFileURL.path)")
    if FileManager.default.fileExists(atPath: dictionaryFileURL.path) {
      Logger.log("Dictionary file exists. Loading from disk.")
      do {
        let data = try Data(contentsOf: dictionaryFileURL)
        let dictionaryData = try JSONDecoder().decode(DictionaryData.self, from: data)
        
        var tempPtEnDict: [String: String] = [:]
        var tempEnPtDict: [String: String] = [:]
        for entry in dictionaryData.words {
          tempPtEnDict[entry.targetWord.lowercased()] = entry.englishWord
          tempEnPtDict[entry.englishWord.lowercased()] = entry.targetWord
        }
        ptEnDict = tempPtEnDict
        enPtDict = tempEnPtDict
        
        Logger.log("Successfully loaded and decoded dictionary.")
        completion(true)
      } catch {
        Logger.log("Error loading or decoding dictionary from disk: \(error)")
        completion(false)
      }
    } else {
      Logger.log("Dictionary file does not exist. Starting download.")
      downloadDictionary(completion: completion)
    }
  }
  
  private static func downloadDictionary(completion: @escaping (Bool) -> Void) {
    Logger.log("Downloading from: \(dictionaryURL)")
    let task = URLSession.shared.dataTask(with: dictionaryURL) { data, response, error in
      if let error = error {
        Logger.log("Error downloading dictionary: \(error.localizedDescription)")
        completion(false)
        return
      }
      guard let data = data else {
        Logger.log("No data received from dictionary download.")
        completion(false)
        return
      }
      do {
        try data.write(to: dictionaryFileURL)
        Logger.log("Successfully saved dictionary to: \(dictionaryFileURL.path)")
        
        let dictionaryData = try JSONDecoder().decode(DictionaryData.self, from: data)
        
        var tempPtEnDict: [String: String] = [:]
        var tempEnPtDict: [String: String] = [:]
        for entry in dictionaryData.words {
          tempPtEnDict[entry.targetWord.lowercased()] = entry.englishWord
          tempEnPtDict[entry.englishWord.lowercased()] = entry.targetWord
        }
        ptEnDict = tempPtEnDict
        enPtDict = tempEnPtDict
        
        Logger.log("Successfully decoded downloaded dictionary.")
        completion(true)
      } catch {
        Logger.log("Error saving or decoding downloaded dictionary: \(error)")
        completion(false)
      }
    }
    task.resume()
  }
  
  /// Look up in the Portuguese-English dictionary.
  static func define(_ word: String) -> String? {
    return ptEnDict?[word.lowercased()]
  }
  
  /// Search all dictionaries for a translation between PT and EN.
  static func dictionaryTranslate(_ text: String, from: String, to: String) -> String? {
    if from == "en" && to == "pt" {
      return enPtDict?[text.lowercased()]
    } else if from == "pt" && to == "en" {
      return ptEnDict?[text.lowercased()]
    }
    return nil
  }
  
  static func availableDictionaryNames() -> [String] {
    if FileManager.default.fileExists(atPath: dictionaryFileURL.path) {
      return ["Portuguese-English (local)"]
    } else {
      return []
    }
  }
}

