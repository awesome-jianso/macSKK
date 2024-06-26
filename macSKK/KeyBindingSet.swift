// SPDX-FileCopyrightText: 2024 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

struct KeyBindingSet {
    /**
     * 修飾キーを除いたキー入力が同じ場合は修飾キーが多いものが前に来るように並べた配列。
     * 入力に一番合致するキー入力を返すために最初にソートしてもっておく。
     */
    let sorted: [(KeyBinding.Input, KeyBinding.Action)]

    static let defaultKeyBindingSet = KeyBindingSet(KeyBinding.defaultKeyBindingSettings)

    init(_ values: [KeyBinding]) {
        sorted = values.flatMap { keyValue in
            keyValue.inputs.map { ($0, keyValue.action) }
        }.sorted(by: { lts, rts in
            if lts.0.key == rts.0.key {
                return lts.0.modifierFlags.rawValue > rts.0.modifierFlags.rawValue
            } else {
                switch (lts.0.key, rts.0.key) {
                case let (.character(l), .character(r)):
                    return l < r
                case let (.code(l), .code(r)):
                    return l < r
                // .character, .codeはどういう順序で並んでいてもいいので、いったん`.code < .character`としておく。
                case (.character, .code):
                    return false
                case (.code, .character):
                    return true
                }
            }
        })
    }

    func action(event: NSEvent) -> KeyBinding.Action? {
        sorted.first(where: { $0.0.accepts(event: event) })?.1
    }
}
