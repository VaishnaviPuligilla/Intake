// IngredientInsightEngine.swift
// Offline knowledge-based ingredient analysis engine.
// Performs tokenization, similarity correction, rule matching,
// and risk-aware insight inference using local reference rules.
import Foundation
import NaturalLanguage

struct IngredientRule {
    let keyword: String
    let aliases: [String]
    let risk: String
    let category: String
    let messages: [String]
    let benefits: [String]
    var allTerms: [String] { [keyword] + aliases }
}

struct Insight {
    let message: String
    let risk: String
    let matchedIngredients: [String]
    let benefits: [String]
}

struct SingleIngredientInsight: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let risk: String
    let insight: String
    let benefits: [String]
}

struct WeeklyReflection {
    let dominantRisk: String
    let safeCount: Int
    let moderateCount: Int
    let carefulCount: Int
    let topBenefits: [String]
    let summary: String
    let encouragement: String
}

struct HealthEntrySnapshot {
    let productName: String
    let ingredientsText: String
    let riskLevel: String
    let consumedDate: Date
}

private struct IngredientRuleJSON: Codable {
    let keyword: String
    let aliases: [String]
    let risk: String
    let category: String
    let messages: [String]
    let benefits: [String]
}

final class IngredientInsightEngine {
    static let shared = IngredientInsightEngine()
    private init() {}

    private var _rules: [IngredientRule]?
    private var rules: [IngredientRule] {
        if let r = _rules { return r }
        let loaded = loadRules()
        _rules = loaded
        return loaded
    }

    private lazy var knownTermsSet: Set<String> = {
        Set(rules.flatMap { $0.allTerms.map { $0.lowercased() } })
    }()

    private lazy var knownWordsByFirstLetter: [Character: [String]] = {
        var buckets: [Character: Set<String>] = [:]
        for term in rules.flatMap({ $0.allTerms.map { $0.lowercased() } }) {
            for word in term.split(separator: " ").map(String.init) {
                guard word.count >= 3, let c = word.first, c.isLetter else { continue }
                buckets[c, default: []].insert(word)
            }
        }
        return buckets.mapValues { Array($0) }
    }()

    private let junkTokens: Set<String> = [
        "share", "save", "cancel", "close", "done", "back", "next", "ok", "open",
        "panel", "panels", "visit", "and", "or", "the", "for", "with", "from",
        "generally safe", "generally", "safe", "careful", "moderate",
        "food ingredient", "food", "ingredient", "ingredients",
        "ingredient analysis", "ingredients found",
        // Nutrition
        "nutrition facts", "nutritional information", "allergen", "allergy",
        "may contain", "contains", "serving", "servings", "storage",
        "direction", "directions", "manufactured", "distributed", "packed",
        "mfg", "mfd", "expiry", "exp", "best before", "use by",
        
        "a", "an", "as", "at", "be", "by", "do", "go", "he", "if",
        "in", "is", "it", "me", "my", "no", "of", "on", "so", "to",
        "up", "us", "we", "are", "was", "were", "has", "have", "had",
        "this", "that", "these", "those", "not", "can", "may", "will",
        "should", "also", "then", "than", "more", "less", "very",
    ]

    private let garbleRegexes: [NSRegularExpression] = {
        let patterns = [
            "^[bcdfghjklmnpqrstvwxyz]{4,}$",  // consonants
            "^[^a-z]+$",                        // no letters
            "\\d{4,}",                          // 4+ digits in a row
            "^.{1,2}$",                         // 1–2 characters
            "^.{51,}$",                         // over 50 chararcters
            "^[!@#\\$%\\^&\\*\\(\\)_\\+=\\[\\]\\{\\}\\|\\\\<>\\?/~`]", // starting with symbol
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private func loadRules() -> [IngredientRule] {
        if let url  = Bundle.main.url(forResource: "ingredient_rules", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([IngredientRuleJSON].self, from: data),
           !decoded.isEmpty {
            return decoded.map {
                IngredientRule(
                    keyword:  $0.keyword.lowercased(),
                    aliases:  $0.aliases.map { $0.lowercased() },
                    risk:     $0.risk,
                    category: $0.category,
                    messages: $0.messages,
                    benefits: $0.benefits
                )
            }
        }
        return builtInRules()
    }

    private func builtInRules() -> [IngredientRule] {
        [
            IngredientRule(keyword: "sugar", aliases: ["sucrose", "cane sugar", "beet sugar", "raw sugar"],
                           risk: "moderate", category: "Simple Carbohydrate",
                           messages: ["Sugar is a simple carbohydrate that provides quick energy. Excess consumption raises blood glucose sharply.",
                                      "A primary energy source, but high intake contributes to insulin resistance."],
                           benefits: ["Quick energy", "Enhances flavour"]),

            IngredientRule(keyword: "high fructose corn syrup", aliases: ["hfcs", "corn syrup", "glucose-fructose syrup"],
                           risk: "careful", category: "Processed Sweetener",
                           messages: ["HFCS is a highly processed sweetener linked to metabolic syndrome.",
                                      "Associated with fatty liver and elevated triglycerides at high doses."],
                           benefits: []),

            IngredientRule(keyword: "stevia", aliases: ["stevia extract", "rebiana", "reb a", "steviol glycoside"],
                           risk: "safe", category: "Natural Sweetener",
                           messages: ["Stevia is a plant-derived zero-calorie sweetener that does not spike blood glucose.",
                                      "Well-studied and safe for most people, including diabetics."],
                           benefits: ["Zero calories", "Blood-sugar neutral", "Plant-derived"]),

            IngredientRule(keyword: "palm oil", aliases: ["palm fat", "refined palm oil"],
                           risk: "moderate", category: "Saturated Fat",
                           messages: ["Palm oil is high in saturated fatty acids. Regular high consumption may raise LDL cholesterol.",
                                      "Provides texture and shelf stability but lacks the beneficial profile of olive oil."],
                           benefits: ["Heat stable"]),

            IngredientRule(keyword: "hydrogenated oil", aliases: ["partially hydrogenated", "trans fat", "hydrogenated vegetable oil", "shortening"],
                           risk: "careful", category: "Trans Fat",
                           messages: ["Hydrogenated oils contain artificial trans fats strongly linked to cardiovascular disease risk.",
                                      "Most health authorities recommend limiting trans fats to as close to zero as possible."],
                           benefits: []),

            IngredientRule(keyword: "olive oil", aliases: ["extra virgin olive oil", "evoo"],
                           risk: "safe", category: "Monounsaturated Fat",
                           messages: ["Olive oil is rich in monounsaturated fatty acids and polyphenol antioxidants.",
                                      "A cornerstone of the Mediterranean diet."],
                           benefits: ["Heart health", "Antioxidants", "Anti-inflammatory"]),

            IngredientRule(keyword: "whey protein", aliases: ["whey", "whey protein concentrate", "whey protein isolate"],
                           risk: "safe", category: "Animal Protein",
                           messages: ["Whey protein is a complete protein highly effective for muscle repair and growth."],
                           benefits: ["Complete protein", "Muscle repair", "High bioavailability"]),

            IngredientRule(keyword: "soy lecithin", aliases: ["sunflower lecithin", "lecithin"],
                           risk: "safe", category: "Emulsifier",
                           messages: ["Lecithin is a natural emulsifier that also supplies choline for brain and liver function."],
                           benefits: ["Choline source", "Natural emulsifier"]),

            IngredientRule(keyword: "wheat flour", aliases: ["refined flour", "white flour", "enriched flour", "plain flour", "all-purpose flour"],
                           risk: "moderate", category: "Refined Carbohydrate",
                           messages: ["Refined wheat flour digests quickly, causing rapid blood glucose spikes."],
                           benefits: ["Energy source"]),

            IngredientRule(keyword: "whole wheat", aliases: ["whole grain wheat", "wholemeal flour", "whole wheat flour"],
                           risk: "safe", category: "Complex Carbohydrate",
                           messages: ["Whole wheat retains fibre, B vitamins, and minerals for better gut health and stable blood sugar."],
                           benefits: ["Dietary fibre", "B vitamins", "Lower GI"]),

            IngredientRule(keyword: "oat", aliases: ["oats", "rolled oats", "oat flour", "oatmeal"],
                           risk: "safe", category: "Complex Carbohydrate",
                           messages: ["Oats are rich in beta-glucan, which lowers LDL cholesterol and supports gut health."],
                           benefits: ["Beta-glucan fibre", "Heart health", "Blood sugar regulation"]),

            IngredientRule(keyword: "sodium benzoate", aliases: ["benzoate", "e211"],
                           risk: "careful", category: "Preservative",
                           messages: ["Sodium benzoate can convert to benzene with vitamin C. Associated with hyperactivity in children."],
                           benefits: ["Extends shelf life"]),

            IngredientRule(keyword: "monosodium glutamate", aliases: ["msg", "e621", "glutamate"],
                           risk: "moderate", category: "Flavour Enhancer",
                           messages: ["MSG is a sodium salt of glutamic acid. Extensive research has not confirmed 'MSG sensitivity' in most people."],
                           benefits: ["Umami flavour enhancement"]),

            IngredientRule(keyword: "sodium bicarbonate", aliases: ["baking soda", "bicarbonate of soda", "e500"],
                           risk: "safe", category: "Leavening Agent",
                           messages: ["Sodium bicarbonate is a safe leavening agent well tolerated at normal food amounts."],
                           benefits: ["Leavening"]),

            IngredientRule(keyword: "citric acid", aliases: ["e330"],
                           risk: "safe", category: "Acidulant / Preservative",
                           messages: ["Citric acid is a natural organic acid from citrus fruits, widely used and considered very safe."],
                           benefits: ["Natural preservative", "Flavour enhancement"]),

            IngredientRule(keyword: "potassium sorbate", aliases: ["e202", "sorbate"],
                           risk: "moderate", category: "Preservative",
                           messages: ["Potassium sorbate inhibits mould and yeast. Low risk at food-level doses."],
                           benefits: ["Prevents mould", "Extends shelf life"]),

            IngredientRule(keyword: "vitamin e", aliases: ["tocopherol", "mixed tocopherols", "alpha tocopherol", "e306", "e307"],
                           risk: "safe", category: "Fat-Soluble Vitamin / Antioxidant",
                           messages: ["Vitamin E is a fat-soluble antioxidant that protects cells from oxidative damage."],
                           benefits: ["Antioxidant protection", "Immune support", "Skin health"]),

            IngredientRule(keyword: "vitamin c", aliases: ["ascorbic acid", "l-ascorbic acid", "ascorbate", "e300"],
                           risk: "safe", category: "Water-Soluble Vitamin",
                           messages: ["Vitamin C is an essential antioxidant important for collagen synthesis and immune defence."],
                           benefits: ["Immune support", "Collagen synthesis", "Iron absorption aid"]),

            IngredientRule(keyword: "natural flavour", aliases: ["natural flavor", "natural flavouring", "natural flavoring"],
                           risk: "moderate", category: "Flavouring",
                           messages: ["'Natural flavour' is a broad regulatory term. The specific compounds are not always disclosed."],
                           benefits: []),

            IngredientRule(keyword: "artificial flavour", aliases: ["artificial flavor", "artificial flavoring"],
                           risk: "moderate", category: "Artificial Flavouring",
                           messages: ["Artificial flavours are synthesised compounds offering no nutritional value."],
                           benefits: []),

            IngredientRule(keyword: "salt", aliases: ["sodium chloride", "sea salt", "himalayan salt", "kosher salt"],
                           risk: "moderate", category: "Mineral / Electrolyte",
                           messages: ["Salt is essential for fluid balance but high sodium intake is linked to elevated blood pressure."],
                           benefits: ["Electrolyte balance", "Nerve function"]),

            IngredientRule(keyword: "dietary fibre", aliases: ["dietary fiber", "soluble fibre", "insoluble fiber", "prebiotic fibre", "inulin", "psyllium"],
                           risk: "safe", category: "Dietary Fibre / Prebiotic",
                           messages: ["Dietary fibre supports digestive health, feeds beneficial gut bacteria, and contributes to satiety."],
                           benefits: ["Gut health", "Prebiotic effect", "Satiety"]),

            IngredientRule(keyword: "peanut", aliases: ["groundnut", "peanut oil", "arachis oil", "peanut butter"],
                           risk: "careful", category: "Legume / Allergen",
                           messages: ["Peanuts are a common allergen that can cause severe anaphylaxis in sensitive individuals."],
                           benefits: ["Protein source", "Healthy fats"]),

            IngredientRule(keyword: "milk", aliases: ["dairy", "cream", "milk powder", "whole milk", "skimmed milk", "dried milk", "milk solids", "lactose"],
                           risk: "moderate", category: "Animal Protein / Allergen",
                           messages: ["Milk provides complete protein, calcium, and vitamin D. Lactose intolerance affects many adults."],
                           benefits: ["Calcium", "Complete protein", "Vitamin B12"]),

            IngredientRule(keyword: "egg", aliases: ["whole egg", "egg white", "egg yolk", "albumin", "egg powder", "dried egg"],
                           risk: "safe", category: "Animal Protein",
                           messages: ["Eggs are among the most nutritionally complete foods with all essential amino acids and choline."],
                           benefits: ["Complete protein", "Choline", "Vitamins A, D, E, K"]),

            IngredientRule(keyword: "cocoa", aliases: ["cocoa powder", "cocoa butter", "cacao", "cacao powder"],
                           risk: "safe", category: "Plant Compound / Antioxidant",
                           messages: ["Cocoa is rich in flavanols associated with improved blood flow and cognitive benefits."],
                           benefits: ["Flavanols", "Antioxidants", "Magnesium"]),

            IngredientRule(keyword: "soy", aliases: ["soya", "soybean", "tofu", "tempeh", "edamame", "soy protein", "isolated soy protein"],
                           risk: "safe", category: "Plant Protein / Phytoestrogen",
                           messages: ["Soy is a complete plant protein. At normal dietary intake, isoflavones are safe for most adults."],
                           benefits: ["Complete plant protein", "Cholesterol reduction"]),

            IngredientRule(keyword: "maltodextrin", aliases: ["corn maltodextrin", "tapioca maltodextrin"],
                           risk: "moderate", category: "Processed Carbohydrate",
                           messages: ["Maltodextrin is a fast-digesting carbohydrate that can raise blood glucose quickly."],
                           benefits: ["Texture stability"]),

            IngredientRule(keyword: "disodium inosinate", aliases: ["e631", "inosinate"],
                           risk: "moderate", category: "Flavour Enhancer",
                           messages: ["Disodium inosinate is a flavour enhancer often paired with MSG in savoury foods."],
                           benefits: ["Umami enhancement"]),

            IngredientRule(keyword: "disodium guanylate", aliases: ["e627", "guanylate"],
                           risk: "moderate", category: "Flavour Enhancer",
                           messages: ["Disodium guanylate boosts savoury flavour intensity in processed foods."],
                           benefits: ["Flavour enhancement"]),

            IngredientRule(keyword: "yeast extract", aliases: ["autolyzed yeast extract"],
                           risk: "moderate", category: "Flavouring",
                           messages: ["Yeast extract is used to add umami flavour; generally safe at food-level intake."],
                           benefits: ["Umami flavour"]),

            IngredientRule(keyword: "corn starch", aliases: ["maize starch", "cornflour", "starch"],
                           risk: "safe", category: "Carbohydrate / Thickener",
                           messages: ["Corn starch is a common thickener and carbohydrate source in packaged foods."],
                           benefits: ["Texture and thickening"]),

            IngredientRule(keyword: "modified starch", aliases: ["modified food starch", "modified corn starch"],
                           risk: "moderate", category: "Stabiliser",
                           messages: ["Modified starch improves texture and shelf stability in processed products."],
                           benefits: ["Texture stability"]),

            IngredientRule(keyword: "sucralose", aliases: ["e955"],
                           risk: "moderate", category: "Artificial Sweetener",
                           messages: ["Sucralose is a zero-calorie sweetener; generally safe within acceptable intake levels."],
                           benefits: ["Low calorie sweetness"]),

            IngredientRule(keyword: "acesulfame potassium", aliases: ["acesulfame k", "ace-k", "e950"],
                           risk: "moderate", category: "Artificial Sweetener",
                           messages: ["Acesulfame potassium is a non-nutritive sweetener often blended with sucralose."],
                           benefits: ["Low calorie sweetness"]),

            IngredientRule(keyword: "turmeric", aliases: ["turmeric powder", "haldi", "curcuma"],
                           risk: "safe", category: "Spice",
                           messages: ["Turmeric contains curcuminoids with antioxidant and anti-inflammatory potential."],
                           benefits: ["Antioxidants"]),

            IngredientRule(keyword: "garam masala", aliases: ["masala mix", "spice mix"],
                           risk: "safe", category: "Spice Blend",
                           messages: ["Garam masala is a spice blend commonly used for flavour in Indian foods."],
                           benefits: ["Flavour complexity"]),
        ]
    }

    private func extractTokenSet(from text: String) -> Set<String> {
        let lower = text.lowercased()
        var tokens = Set<String>()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = lower
        tokenizer.enumerateTokens(in: lower.startIndex..<lower.endIndex) { range, _ in
            let word = String(lower[range])
            if word.count > 1 { tokens.insert(word) }
            return true
        }
        return tokens
    }

    private func termMatchesText(_ term: String, text: String, tokens: Set<String>) -> Bool {
        let words = term.split(separator: " ").map(String.init)
        if words.count == 1 {
            if tokens.contains(words[0]) { return true }
            return matchesWordBoundary(words[0], in: text)
        }
        return text.contains(term)
    }

    private func matchesWordBoundary(_ word: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let pattern = "(?<![a-z0-9\\-])\(escaped)(?![a-z0-9\\-])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private func ruleMatches(_ rule: IngredientRule, in text: String, tokens: Set<String>) -> Bool {
        rule.allTerms.contains { termMatchesText($0, text: text, tokens: tokens) }
    }

    private func escalatedRisk(_ a: String, _ b: String) -> String {
        let order = ["safe": 0, "moderate": 1, "careful": 2]
        return (order[b] ?? 0) > (order[a] ?? 0) ? b : a
    }

    private func riskOrder(_ risk: String) -> Int {
        switch risk { case "careful": return 2; case "moderate": return 1; default: return 0 }
    }

    private func pickMessage(from messages: [String], seed: String) -> String {
        guard !messages.isEmpty else { return "" }
        return messages[abs(seed.hashValue) % messages.count]
    }

    func analyze(ingredients: String) -> Insight {
        guard !ingredients.isEmpty else {
            return Insight(message: "", risk: "safe", matchedIngredients: [], benefits: [])
        }
        let lower  = ingredients.lowercased()
        let tokens = extractTokenSet(from: lower)
        var bestRisk   = "safe"
        var primaryMsg = ""
        var matched    = [String]()
        var benefits   = [String]()

        for rule in rules {
            guard ruleMatches(rule, in: lower, tokens: tokens) else { continue }
            bestRisk = escalatedRisk(bestRisk, rule.risk)
            if primaryMsg.isEmpty {
                primaryMsg = pickMessage(from: rule.messages, seed: lower + rule.keyword)
            }
            let name = rule.keyword.capitalized
            if !matched.contains(name) { matched.append(name) }
            for b in rule.benefits where !benefits.contains(b) { benefits.append(b) }
        }
        if primaryMsg.isEmpty {
            primaryMsg = "Ingredients look straightforward. Enjoy mindfully."
        }
        return Insight(
            message:            primaryMsg,
            risk:               bestRisk,
            matchedIngredients: matched,
            benefits:           Array(benefits.prefix(5))
        )
    }

    func detailedInsights(ingredients: String) -> [SingleIngredientInsight] {
        guard !ingredients.isEmpty else { return [] }
        let lower  = ingredients.lowercased()
        let tokens = extractTokenSet(from: lower)
        var results = [SingleIngredientInsight]()
        var seen    = Set<String>()

        for rule in rules {
            guard !seen.contains(rule.keyword),
                  ruleMatches(rule, in: lower, tokens: tokens) else { continue }
            seen.insert(rule.keyword)
            results.append(SingleIngredientInsight(
                name:     rule.keyword.capitalized,
                category: rule.category,
                risk:     rule.risk,
                insight:  pickMessage(from: rule.messages, seed: lower + rule.keyword),
                benefits: rule.benefits
            ))
        }
        let rawIngredients = extractCleanRawIngredients(from: ingredients)
        for raw in rawIngredients {
            let lowRaw = raw.lowercased().trimmingCharacters(in: .whitespaces)
            if lowRaw.count < 2 { continue }
            
            let alreadyCovered = seen.contains(where: { lowRaw.contains($0) || $0.contains(lowRaw) })
            if alreadyCovered { continue }

            if let matchedRule = rules.first(where: { rule in
                rule.allTerms.contains { term in
                    let t = term.lowercased()
                    return lowRaw.contains(t) || t.contains(lowRaw)
                }
            }), !seen.contains(matchedRule.keyword) {
                seen.insert(matchedRule.keyword)
                results.append(SingleIngredientInsight(
                    name:     matchedRule.keyword.capitalized,
                    category: matchedRule.category,
                    risk:     matchedRule.risk,
                    insight:  pickMessage(from: matchedRule.messages, seed: lowRaw + matchedRule.keyword),
                    benefits: matchedRule.benefits
                ))
                continue
            }

            if !isPlausibleIngredientToken(lowRaw) { continue }

            results.append(SingleIngredientInsight(
                name:     raw.trimmingCharacters(in: .whitespaces).capitalized,
                category: inferCategory(from: lowRaw),
                risk:     "safe",
                insight:  "This ingredient is present in the product. No specific risk data available — generally considered safe at food-level amounts.",
                benefits: []
            ))
        }

        return results.sorted { riskOrder($0.risk) > riskOrder($1.risk) }
    }

    private func extractCleanRawIngredients(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(60)
            .map { $0 }
    }

    private func isPlausibleIngredientToken(_ lower: String) -> Bool {
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines)

        if junkTokens.contains(trimmed) { return false }

        if trimmed.count < 2 || trimmed.count > 60 { return false }

        let letterCount = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        if letterCount < 1 { return false }

        let digitCount = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        if digitCount > 6 { return false }

        let wordCount = trimmed.split(separator: " ").count
        if wordCount > 10 { return false }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for regex in garbleRegexes {
            if regex.firstMatch(in: trimmed, range: range) != nil { return false }
        }

        if let first = trimmed.first, "!@#$%^&*()_+=[]{}|\\<>?/~`*".contains(first) { return false }

        let junkPhrases = [
            "generally safe", "food ingredient", "ingredient analysis",
            "nutrition facts", "may contain", "allergy advice", "best before",
            "use by", "expiry date", "panel", "visit us", "share this",
        ]
        for phrase in junkPhrases {
            if trimmed.contains(phrase) { return false }
        }

        return true
    }

    private func inferCategory(from ingredient: String) -> String {
        let i = ingredient.lowercased()
        if i.contains("oil") || i.contains("fat") || i.contains("butter") { return "Fat" }
        if i.contains("flour") || i.contains("starch") || i.contains("syrup") { return "Carbohydrate" }
        if i.contains("protein") || i.contains("whey") || i.contains("casein") { return "Protein" }
        if i.contains("vitamin") || i.contains("mineral") || i.contains("calcium") || i.contains("iron") { return "Micronutrient" }
        if i.contains("colour") || i.contains("color") || i.contains("dye") { return "Artificial Additive" }
        if i.contains("preserv") || i.contains("sorbate") || i.contains("benzoate") { return "Preservative" }
        if i.contains("emulsif") || i.contains("lecithin") { return "Emulsifier" }
        if i.contains("flavour") || i.contains("flavor") || i.contains("extract") { return "Flavouring" }
        if i.contains("salt") || i.contains("sodium") { return "Electrolyte" }
        if i.contains("fibre") || i.contains("fiber") { return "Dietary Fibre" }
        if i.contains("sugar") || i.contains("syrup") || i.contains("glucose") { return "Sweetener" }
        if i.contains("acid") { return "Acid / Preservative" }
        if i.contains("gum") || i.contains("starch") { return "Stabiliser" }
        return "Food Ingredient"
    }

    func isKnownIngredientName(_ raw: String) -> Bool {
        let candidate = raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !candidate.isEmpty else { return false }
        guard isPlausibleIngredientToken(candidate) else { return false }

        let text = candidate
        let tokens = extractTokenSet(from: text)
        for rule in rules {
            for term in rule.allTerms.map({ $0.lowercased() }) {
                if termMatchesText(term, text: text, tokens: tokens) {
                    return true
                }
            }
        }
        return false
    }

    func normalizedOCRIngredientPhrase(_ raw: String) -> String? {
        let candidate = raw
            .lowercased()
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        guard !candidate.isEmpty else { return nil }
        guard isPlausibleIngredientToken(candidate) else { return nil }

        let blockedPhrases = [
            "this product", "contains", "may contain", "nutrition", "serving size",
            "energy", "direction", "storage", "best before", "expiry", "use by"
        ]
        if blockedPhrases.contains(where: { candidate.contains($0) }) { return nil }

        if isKnownIngredientName(candidate) { return candidate }

        let words = candidate.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        let corrected = words.map { word -> String in
            guard word.count >= 4, let first = word.first else { return word }
            guard let bucket = knownWordsByFirstLetter[first.lowercased().first ?? first], !bucket.isEmpty else {
                return word
            }
            var bestWord = word
            var bestScore = 0.0
            for known in bucket where abs(known.count - word.count) <= 2 {
                let score = similarity(word, known)
                if score > bestScore {
                    bestScore = score
                    bestWord = known
                }
            }
            return bestScore >= 0.84 ? bestWord : word
        }

        let phrase = corrected.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return nil }

        if isKnownIngredientName(phrase) { return phrase }

        let hasKnownWord = phrase.split(separator: " ").contains { word in
            let w = String(word)
            return knownTermsSet.contains(w) || isKnownIngredientName(w)
        }
        return hasKnownWord ? phrase : nil
    }

    private func similarity(_ a: String, _ b: String) -> Double {
        let dist = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1.0 }
        return 1.0 - (Double(dist) / Double(maxLen))
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let lhs = Array(a)
        let rhs = Array(b)
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var prev = Array(0...rhs.count)
        for (i, lc) in lhs.enumerated() {
            var curr = Array(repeating: 0, count: rhs.count + 1)
            curr[0] = i + 1
            for (j, rc) in rhs.enumerated() {
                let cost = lc == rc ? 0 : 1
                curr[j + 1] = min(
                    prev[j + 1] + 1,     // deletion
                    curr[j] + 1,         // insertion
                    prev[j] + cost       // substitution
                )
            }
            prev = curr
        }
        return prev[rhs.count]
    }

    func weeklyReflection(from entries: [HealthEntrySnapshot]) -> WeeklyReflection {
        guard !entries.isEmpty else {
            return WeeklyReflection(
                dominantRisk: "safe", safeCount: 0, moderateCount: 0, carefulCount: 0,
                topBenefits: [], summary: "No products logged this week.",
                encouragement: "Weekly view shows only your logged products."
            )
        }
        var safe = 0, moderate = 0, careful = 0
        for entry in entries {
            switch entry.riskLevel {
            case "careful":  careful  += 1
            case "moderate": moderate += 1
            default:         safe     += 1
            }
        }
        let total = entries.count
        let dominantRisk: String
        if careful  > total / 3 { dominantRisk = "careful"  }
        else if moderate > safe { dominantRisk = "moderate" }
        else                    { dominantRisk = "safe"     }

        let summary     = buildSummary(safe: safe, moderate: moderate, careful: careful, total: total)
        return WeeklyReflection(
            dominantRisk: dominantRisk,
            safeCount: safe,
            moderateCount: moderate,
            carefulCount: careful,
            topBenefits: [],
            summary: summary,
            encouragement: "Weekly view shows only your logged products."
        )
    }

    private func buildSummary(safe: Int, moderate: Int, careful: Int, total: Int) -> String {
        var parts = [String]()
        if safe     > 0 { parts.append("\(safe) low-concern") }
        if moderate > 0 { parts.append("\(moderate) moderate") }
        if careful  > 0 { parts.append("\(careful) worth-watching") }
        return "This week: " + parts.joined(separator: ", ") + "."
    }

}
