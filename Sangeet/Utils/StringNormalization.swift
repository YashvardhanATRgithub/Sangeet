//
//  StringNormalization.swift
//  HiFidelity
//
//  String normalization utilities for searching, deduplication, and sorting
//  Based on industry standards (MusicBrainz, iTunes)
//

import Foundation

// MARK: - Main Normalization

extension String {
    /// Normalizes string for searching and identification
    /// - Removes leading articles (The, A, An)
    /// - Unicode NFC normalization
    /// - Case folding (better than lowercase)
    /// - Removes diacritics
    /// - Trims whitespace
    /// - Removes special characters
    var normalized: String {
        var result = self.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove leading articles (English only for search)
        let articles = ["the ", "a ", "an "]
        let lowerResult = result.lowercased()
        for article in articles {
            if lowerResult.hasPrefix(article) {
                result = String(result.dropFirst(article.count))
                break
            }
        }
        
        // Unicode NFC normalization (ensures consistent representation)
        result = result.precomposedStringWithCanonicalMapping
        
        // Case folding (handles special cases like German ß → ss)
        result = result.folding(options: .caseInsensitive, locale: nil)
        
        // Remove diacritics (é → e, ñ → n)
        result = result.folding(options: .diacriticInsensitive, locale: nil)
        
        // Normalize common punctuation
        result = result
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "+", with: "plus")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "'", with: "")
        
        // Remove special characters, keep only alphanumeric and spaces
        result = result.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined(separator: " ")
        
        // Collapse multiple spaces into one
        result = result.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        return result
    }
    
    /// Creates a sort-friendly version by moving articles to the end
    /// "The Beatles" → "Beatles, The"
    /// "El Camino" → "Camino, El"
    /// Based on MusicBrainz standards
    var sortName: String {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Articles to handle (multi-language support)
        let articlesMap: [(language: String, articles: [String])] = [
            ("en", ["the", "a", "an"]),
            ("es", ["el", "la", "los", "las"]),
            ("fr", ["le", "la", "les", "l'"]),
            ("de", ["der", "die", "das"]),
            ("it", ["il", "lo", "la", "i", "gli", "le"]),
            ("pt", ["o", "a", "os", "as"])
        ]
        
        // Check each language's articles
        for (_, articles) in articlesMap {
            for article in articles {
                let pattern = "^(\(article))\\s+(.+)$"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(trimmed.startIndex..., in: trimmed)
                    if let match = regex.firstMatch(in: trimmed, range: range) {
                        let articleRange = Range(match.range(at: 1), in: trimmed)!
                        let restRange = Range(match.range(at: 2), in: trimmed)!
                        let articlePart = String(trimmed[articleRange])
                        let restPart = String(trimmed[restRange])
                        return "\(restPart), \(articlePart)"
                    }
                }
            }
        }
        
        return trimmed
    }
}

// MARK: - Examples & Usage

/*
 # Normalization Examples
 
 ## For Searching (normalized)
 "The Beatles".normalized       // "beatles"
 "Beyoncé".normalized           // "beyonce"
 "A Tribe Called Quest".normalized  // "tribe called quest"
 "AC/DC".normalized             // "ac dc"
 "Björk".normalized             // "bjork"
 "  The  Rolling   Stones  ".normalized  // "rolling stones"
 
 ## For Sorting (sortName)
 "The Beatles".sortName         // "Beatles, The"
 "A Tribe Called Quest".sortName  // "Tribe Called Quest, A"
 "El Camino".sortName           // "Camino, El"  (Spanish)
 "Les Misérables".sortName      // "Misérables, Les"  (French)
 "Der Dritte Raum".sortName     // "Dritte Raum, Der"  (German)
 "Beatles".sortName             // "Beatles"  (no article)
 
 # Usage in Database Operations
 
 ## Creating entities
 let name = "The Beatles"
 var artist = Artist(
     name: name,                    // Display: "The Beatles"
     sortName: name.sortName,       // Sort: "Beatles, The"
     normalizedName: name.normalized  // Search: "beatles"
 )
 
 ## Searching
 let query = "beatles"
 let normalized = query.normalized
 let results = try Artist
     .filter(Artist.Columns.normalizedName.like("%\(normalized)%"))
     .fetchAll(db)
 
 ## Sorting in UI
 let sorted = artists.sorted { $0.sortName < $1.sortName }
 // Results: "Beatles, The", "Rolling Stones, The", "Who, The"
 
 # Why Two Fields?
 
 - name: Display to user ("The Beatles")
 - sortName: Alphabetical ordering ("Beatles, The")
 - normalizedName: Searching and deduplication ("beatles")
 
 This matches industry standards (iTunes, MusicBrainz)
 */

