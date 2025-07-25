// SPDX-FileCopyrightText: 2023 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import Combine

@testable import macSKK

final class UserDictTests: XCTestCase {
    @MainActor func testRefer() throws {
        let dict1 = MemoryDict(entries: ["い": [Word("胃"), Word("伊"), Word("位")]], readonly: true, saveToUserDict: false)
        let dict2 = MemoryDict(entries: ["い": [Word("胃"), Word("意")]], readonly: true, saveToUserDict: true)
        let userDict = try UserDict(dicts: [dict1, dict2],
                                    userDictEntries: ["い": [Word("井"), Word("伊")]],
                                    privateMode: CurrentValueSubject<Bool, Never>(false),
                                    ignoreUserDictInPrivateMode: CurrentValueSubject<Bool, Never>(false),
                                    findCompletionFromAllDicts: CurrentValueSubject<Bool, Never>(false),
                                    dateYomis: [],
                                    dateConversions: [])
        XCTAssertEqual(userDict.refer("い").map { $0.word }, ["井", "伊"], "UserDictのエントリだけを返す")
        XCTAssertEqual(userDict.referDicts("い").map { $0.word }, ["井", "伊", "胃", "位", "意"])
        XCTAssertEqual(userDict.referDicts("い").map { $0.saveToUserDict }, [true, true, true, false, true])
    }

    @MainActor func testReferDictsMergeAnnotation() throws {
        let dict1 = MemoryDict(entries: ["い": [Word("胃", annotation: Annotation(dictId: "dict1", text: "d1ann")), Word("伊")]], readonly: true, saveToUserDict: true)
        let dict2 = MemoryDict(entries: ["い": [Word("胃", annotation: Annotation(dictId: "dict2", text: "d2ann")), Word("意")]], readonly: true)
        let userDict = try UserDict(dicts: [dict1, dict2],
                                    userDictEntries: [:],
                                    privateMode: CurrentValueSubject<Bool, Never>(false),
                                    ignoreUserDictInPrivateMode: CurrentValueSubject<Bool, Never>(false),
                                    findCompletionFromAllDicts: CurrentValueSubject<Bool, Never>(false),
                                    dateYomis: [],
                                    dateConversions: [])
        XCTAssertEqual(userDict.referDicts("い").map({ $0.word }), ["胃", "伊", "意"])
        XCTAssertEqual(userDict.referDicts("い").map({ $0.annotations.map({ $0.dictId }) }), [["dict1", "dict2"], [], []], "dict1, dict2に胃が1つずつある")
    }

    @MainActor func testReferDictsWithOption() throws {
        let dict = MemoryDict(entries: ["あき>": [Word("空き")],
                                        "あき": [Word("秋")],
                                        ">し": [Word("氏")],
                                        "し": [Word("詩")]],
                              readonly: true)
        let userDict = try UserDict(dicts: [dict],
                                    userDictEntries: ["あき>": [Word("飽き")],
                                                      "あき": [Word("安芸")],
                                                      ">し": [Word("詞")],
                                                      "し": [Word("士")]],
                                    privateMode: CurrentValueSubject<Bool, Never>(false),
                                    ignoreUserDictInPrivateMode: CurrentValueSubject<Bool, Never>(false),
                                    findCompletionFromAllDicts: CurrentValueSubject<Bool, Never>(false),
                                    dateYomis: [],
                                    dateConversions: [])
        XCTAssertEqual(userDict.referDicts("あき", option: nil), [Candidate("安芸"), Candidate("秋")])
        XCTAssertEqual(userDict.referDicts("あき", option: .prefix), [Candidate("飽き"), Candidate("空き")])
        XCTAssertEqual(userDict.referDicts("あき", option: .suffix), [])
        XCTAssertEqual(userDict.referDicts("し", option: nil), [Candidate("士"), Candidate("詩")])
        XCTAssertEqual(userDict.referDicts("し", option: .suffix), [Candidate("詞"), Candidate("氏")])
        XCTAssertEqual(userDict.referDicts("し", option: .prefix), [])
    }

    func testPrivateMode() throws {
        let privateMode = CurrentValueSubject<Bool, Never>(false)
        let userDict = try UserDict(dicts: [],
                                    userDictEntries: ["い": [Word("位")]],
                                    privateMode: privateMode,
                                    ignoreUserDictInPrivateMode: CurrentValueSubject<Bool, Never>(false),
                                    findCompletionFromAllDicts: CurrentValueSubject<Bool, Never>(false),
                                    dateYomis: [],
                                    dateConversions: [])
        let word = Word("井")
        XCTAssertEqual(userDict.refer("い").map { $0.word }, ["位"])
        privateMode.send(true)
        // addのテスト
        userDict.add(yomi: "い", word: word)
        // referは変化しない
        XCTAssertEqual(userDict.refer("い").map { $0.word }, ["位"])
        // deleteのテスト
        XCTAssertTrue(userDict.delete(yomi: "い", word: "井"))
    }

    @MainActor func testReferDictsDateConversion() throws {
        let userDict = try UserDict(dicts: [],
                                    userDictEntries: ["きょう": [Word("今日")]],
                                    privateMode: CurrentValueSubject<Bool, Never>(false),
                                    ignoreUserDictInPrivateMode: CurrentValueSubject<Bool, Never>(false),
                                    findCompletionFromAllDicts: CurrentValueSubject<Bool, Never>(false),
                                    dateYomis:  [
                                        .init(yomi: "today", relative: .now),
                                        .init(yomi: "yesterday", relative: .yesterday),
                                        .init(yomi: "tomorrow", relative: .tomorrow),
                                        .init(yomi: "きょう", relative: .now),
                                    ],
                                    dateConversions: [
                                        DateConversion(format: "YYYY/MM/dd", locale: .enUS, calendar: .gregorian),
                                        DateConversion(format: "Gy年M月d日", locale: .jaJP, calendar: .japanese),
                                    ])
        let candidatesToday = userDict.referDicts("today")
        XCTAssertEqual(candidatesToday.count, 2)
        XCTAssertTrue(candidatesToday.allSatisfy({ $0.saveToUserDict == false }))
        // 現在時間で変わるので正規表現マッチ。現在時間をDIできるようにしてもいいかも。
        XCTAssertNotNil(candidatesToday[0].word.wholeMatch(of: /\d{4}\/\d{2}\/\d{2}/))
        XCTAssertNotNil(candidatesToday[1].word.wholeMatch(of: /令和\d{1,}年\d{1,2}月\d{1,2}日/))

        let candidatesYesterday = userDict.referDicts("yesterday")
        XCTAssertEqual(candidatesYesterday.count, 2)
        XCTAssertTrue(candidatesYesterday.allSatisfy({ $0.saveToUserDict == false }))
        XCTAssertNotNil(candidatesYesterday[0].word.wholeMatch(of: /\d{4}\/\d{2}\/\d{2}/))
        XCTAssertNotNil(candidatesYesterday[1].word.wholeMatch(of: /令和\d{1,}年\d{1,2}月\d{1,2}日/))

        let candidatesTomorrow = userDict.referDicts("tomorrow")
        XCTAssertEqual(candidatesTomorrow.count, 2)
        XCTAssertTrue(candidatesTomorrow.allSatisfy({ $0.saveToUserDict == false }))
        XCTAssertNotNil(candidatesTomorrow[0].word.wholeMatch(of: /\d{4}\/\d{2}\/\d{2}/))
        XCTAssertNotNil(candidatesTomorrow[1].word.wholeMatch(of: /令和\d{1,}年\d{1,2}月\d{1,2}日/))

        let candidatesKyou = userDict.referDicts("きょう")
        XCTAssertEqual(candidatesKyou.count, 3)
        XCTAssertEqual(candidatesKyou.first?.word, "今日") // ユーザー辞書の方が日付変換より前
    }

    func testFindCompletionPrivateMode() throws {
        let privateMode = CurrentValueSubject<Bool, Never>(true)
        let ignoreUserDictInPrivateMode = CurrentValueSubject<Bool, Never>(false)
        let dict1 = MemoryDict(entries: ["にほん": [Word("日本")], "にほ": [Word("2歩")]], readonly: false)
        let dict2 = MemoryDict(entries: ["にほんご": [Word("日本語")]], readonly: false)
        let userDict = try UserDict(dicts: [dict1, dict2],
                                    userDictEntries: ["にふ": [Word("二歩")]],
                                    privateMode: privateMode,
                                    ignoreUserDictInPrivateMode: ignoreUserDictInPrivateMode,
                                    findCompletionFromAllDicts: CurrentValueSubject<Bool, Never>(false),
                                    dateYomis: [],
                                    dateConversions: [])
        // プライベートモード時はユーザー辞書から検索する
        XCTAssertEqual(userDict.findCompletion(prefix: "に"), "にふ")
        ignoreUserDictInPrivateMode.send(true)
        // プライベートモードかつユーザー辞書から検索しない設定のとき
        XCTAssertNil(userDict.findCompletion(prefix: "に"))
        // ユーザー辞書から検索しない設定だがプライベートモードじゃないときはユーザー辞書から検索する
        privateMode.send(false)
        XCTAssertEqual(userDict.findCompletion(prefix: "に"), "にふ")
    }

    func testFindCompletionFromAllDicts() throws {
        let privateMode = CurrentValueSubject<Bool, Never>(false)
        let ignoreUserDictInPrivateMode = CurrentValueSubject<Bool, Never>(false)
        let findCompletionFromAllDicts = CurrentValueSubject<Bool, Never>(false)
        let dict1 = MemoryDict(entries: ["にほん": [Word("日本")], "にほ": [Word("2歩")]], readonly: false)
        let dict2 = MemoryDict(entries: ["にほんご": [Word("日本語")]], readonly: false)
        let userDict = try UserDict(dicts: [dict1, dict2],
                                    userDictEntries: ["にふ": [Word("二歩")]],
                                    privateMode: privateMode,
                                    ignoreUserDictInPrivateMode: ignoreUserDictInPrivateMode,
                                    findCompletionFromAllDicts: findCompletionFromAllDicts,
                                    dateYomis: [],
                                    dateConversions: [])
        XCTAssertNil(userDict.findCompletion(prefix: "")) // 空文字列にはnilを返す
        XCTAssertEqual(userDict.findCompletion(prefix: "に"), "にふ")
        XCTAssertNil(userDict.findCompletion(prefix: "にほ"))
        XCTAssertNil(userDict.findCompletion(prefix: "にほん"))
        XCTAssertNil(userDict.findCompletion(prefix: "にほんご"))
        findCompletionFromAllDicts.send(true)
        XCTAssertEqual(userDict.findCompletion(prefix: "に"), "にふ")
        XCTAssertEqual(userDict.findCompletion(prefix: "にほ"), "にほん")
        XCTAssertEqual(userDict.findCompletion(prefix: "にほん"), "にほんご")
        XCTAssertNil(userDict.findCompletion(prefix: "にほんご"))
    }

    func testFindCompletionDateYomi() throws {
        let userDict = try UserDict(dicts: [],
                                    userDictEntries: ["tower": [Word("塔")]],
                                    privateMode: CurrentValueSubject<Bool, Never>(false),
                                    ignoreUserDictInPrivateMode: CurrentValueSubject<Bool, Never>(false),
                                    findCompletionFromAllDicts: CurrentValueSubject<Bool, Never>(false),
                                    dateYomis: [
                                        .init(yomi: "today", relative: .now),
                                        .init(yomi: "yesterday", relative: .yesterday),
                                        .init(yomi: "tomorrow", relative: .tomorrow),
                                    ],
                                    dateConversions: [])
        XCTAssertNil(userDict.findCompletion(prefix: "")) // 空文字列にはnilを返す
        XCTAssertEqual(userDict.findCompletion(prefix: "to"), "tower")
        XCTAssertEqual(userDict.findCompletion(prefix: "tod"), "today")
        XCTAssertEqual(userDict.findCompletion(prefix: "y"), "yesterday")
    }
}
