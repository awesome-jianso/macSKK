// SPDX-FileCopyrightText: 2023 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/**
 * UserDefaultsのキー。camelCaseでの命名を採用しています。
 * キーを追加するときは macSKKApp#setupUserDefaults で初期設定を設定するようにしてください。
 */
struct UserDefaultsKeys {
    static let dictionaries = "dictionaries"
    static let directModeBundleIdentifiers = "directModeBundleIdentifiers"
    // 選択中のinputSourceID
    static let selectedInputSource = "selectedInputSource"
    static let showAnnotation = "showAnnotation"
    static let inlineCandidateCount = "inlineCandidateCount"
    static let workarounds = "workarounds"
    static let candidatesFontSize = "candidatesFontSize"
    static let annotationFontSize = "annotationFontSize"
    // SKK辞書サーバーへの接続設定
    static let skkservClient = "skkserv"
    // 選択候補パネルから決定するショートカットキー。
    // 初期値は "123456789"。
    static let selectCandidateKeys = "selectCandidateKeys"
    static let findCompletionFromAllDicts = "findCompletionFromAllDicts"
    // 選択中のキーバインド設定ID
    static let selectedKeyBindingSetId = "selectedKeyBindingSetId"
    // キーバインド設定の配列
    static let keyBindingSets = "keyBindingSets"
    // Enterキーで変換候補の確定 + 改行も行う
    static let enterNewLine = "enterNewLine"
    // 補完を表示するか
    static let showCompletion = "showCompletion"
    // 注釈に使用するシステム辞書のID。SystemDict.Kindで定義。
    static let systemDict = "systemDict"
    // 変換候補選択中のバックスペースの挙動
    static let selectingBackspace = "selectingBackspace"
    // カンマ、ピリオド入力時の句読点
    static let punctuation = "punctuation"
    static let privateMode = "privateMode"
    // プライベートモード時に変換候補にユーザー辞書を無視するかどうか
    static let ignoreUserDictInPrivateMode = "ignoreUserDictInPrivateMode"
    // 入力モードのモーダルを表示するかどうか
    static let showInputModePanel = "showInputModePanel"
    // 候補リストの表示方向
    static let candidateListDirection = "candidateListDirection"
    // 日時変換の変換後のリスト
    static let dateConversions = "dateConversions"
}
