import Foundation

/// 任意の値の型が違っても、全体のデコードを失敗させない
nonisolated struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        self.value = try? decoder.singleValueContainer().decode(Value.self)
    }
}

/// 任意の値を読む。無い・型が違うときは nil にする
nonisolated extension KeyedDecodingContainer {
    func lenient<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> Value? {
        (try? decodeIfPresent(Lenient<Value>.self, forKey: key))?.value
    }
}
