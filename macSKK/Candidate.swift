// SPDX-FileCopyrightText: 2023 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/**
 * 変換候補
 */
struct Candidate: Hashable {
    /**
     * 辞書上での表記
     */
    struct Original: Hashable {
        let yomi: String
        let word: Word.Word
    }

    /**
     * 辞書に登録されている読み。数値変換の場合は例外あり。
     * 数値変換の場合辞書上は "だい#1" のように登録されているが、この値は "だい5" のように実際のユーザー入力で置換されたものになる。
     */
    let yomi: String

    /**
     * 変換結果。数値変換の場合は例外あり。
     * 数値変換の場合、辞書には "第#1" のように登録されているが "第5" のようにユーザー入力で置換されている。
     */
    let word: Word.Word

    /**
     * 辞書上の変換結果の表記。現在は数値変換時のみ設定される。
     * 数値変換の場合 "第#1" のような変換フォーマットを表す表記がされている。
     */
    let original: Original?

    /**
     * 注釈。複数の辞書によるものがあればまとめられている。
     */
    private(set) var annotations: [Annotation]

    /**
     * 辞書に登録されている読み。
     */
    var midashi: String {
        original?.yomi ?? yomi
    }

    /**
     * 辞書に登録されている変換候補。
     */
    var candidateString: String {
        original?.word ?? word
    }

    init(yomi: String, word: Word.Word, annotations: [Annotation] = [], original: Original? = nil) {
        self.yomi = yomi
        self.word = word
        self.annotations = annotations
        self.original = original
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(word)
    }

    /// 注釈を追加する。すでに同じテキストをもつ注釈があれば追加されない。
    mutating func appendAnnotations(_ annotations: [Annotation]) {
        for annotation in annotations {
            if self.annotations.allSatisfy({ $0.text != annotation.text }) {
                self.annotations.append(annotation)
            }
        }
    }
}
