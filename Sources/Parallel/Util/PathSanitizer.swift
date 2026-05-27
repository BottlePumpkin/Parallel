import Foundation

enum PathSanitizer {
    /// 브랜치명 등을 디렉토리 안전한 이름으로 변환.
    /// 규칙: 슬래시/공백/특수문자 → '-', 연속된 '-' 압축, 양끝 '-' 제거.
    static func sanitize(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let replaced = raw.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let joined = String(replaced)
        let collapsed = joined.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
