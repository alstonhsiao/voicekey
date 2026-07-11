import Foundation

/// Regex fallback corrections. Mirrors approach-6 `_voice_postprocess.apply_corrections`.
/// Note: this is fallback only — primary correction is done by the LLM.
/// (OpenCC Traditional conversion is intentionally omitted in approach-7; the
///  Cerebras prompt already enforces Traditional Chinese output.)
enum RegexCorrections {
    static func apply(_ text: String, rules: [RegexRule]) -> String {
        var result = text
        for rule in rules {
            var options: NSRegularExpression.Options = []
            if rule.flags.uppercased().contains("IGNORECASE") {
                options.insert(.caseInsensitive)
            }
            guard let re = try? NSRegularExpression(pattern: rule.pattern, options: options) else {
                continue
            }
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, options: [], range: range,
                                                 withTemplate: rule.replacement)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
