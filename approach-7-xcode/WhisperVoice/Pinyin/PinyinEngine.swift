import Foundation

/// Tone-less full pinyin via Foundation's CFStringTransform.
/// Verified to match pypinyin `lazy_pinyin(style=NORMAL)` for the project's
/// actual vocab (蕭淳云→[xiao,chun,yun], 周芷萓→[zhou,zhi,yi], 加模→[jia,mo]).
/// (config `vocab.match.use_tone` is false; tone handling is intentionally omitted.)
enum PinyinEngine {
    static func syllables(_ s: String) -> [String] {
        let mutable = NSMutableString(string: s) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String)
            .split(separator: " ")
            .map(String.init)
    }
}
