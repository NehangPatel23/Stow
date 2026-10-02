import Foundation

enum KeyCode {
    static let `return`: UInt16 = 36
    static let enter: UInt16 = 76
    static let escape: UInt16 = 53
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    static let up: UInt16 = 126
    static let down: UInt16 = 125
    static let c: UInt16 = 8
    static let v: UInt16 = 9
    static let p: UInt16 = 35
    static let s: UInt16 = 1
    static let z: UInt16 = 6

    /// Physical ANSI number-row key codes. They are not sequential.
    static let digits: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
    ]
}
