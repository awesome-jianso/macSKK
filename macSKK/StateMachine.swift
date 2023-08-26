// SPDX-FileCopyrightText: 2022 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Cocoa
import Combine

// ActionによってIMEに関する状態が変更するイベントの列挙
enum InputMethodEvent: Equatable {
    /// 確定文字列
    case fixedText(String)
    /// 下線付きの未確定文字列
    ///
    /// 登録モード時は "[登録：あああ]ほげ" のように長くなる
    case markedText(MarkedText)
    /// qやlなどにより入力モードを変更する
    case modeChanged(InputMode, NSRect)
}

class StateMachine {
    private(set) var state: IMEState
    let inputMethodEvent: AnyPublisher<InputMethodEvent, Never>
    private let inputMethodEventSubject = PassthroughSubject<InputMethodEvent, Never>()
    let candidateEvent: AnyPublisher<Candidates?, Never>
    private let candidateEventSubject = PassthroughSubject<Candidates?, Never>()

    // TODO: inlineCandidateCount, displayCandidateCountを環境設定にするかも
    /// 変換候補パネルを表示するまで表示する変換候補の数
    let inlineCandidateCount = 3
    /// 変換候補パネルに一度に表示する変換候補の数
    let displayCandidateCount = 9

    init(initialState: IMEState = IMEState()) {
        state = initialState
        inputMethodEvent = inputMethodEventSubject.eraseToAnyPublisher()
        candidateEvent = candidateEventSubject.removeDuplicates().eraseToAnyPublisher()
    }

    func handle(_ action: Action) -> Bool {
        switch state.inputMethod {
        case .normal:
            return handleNormal(action, specialState: state.specialState)
        case .composing(let composing):
            return handleComposing(action, composing: composing, specialState: state.specialState)
        case .selecting(let selecting):
            return handleSelecting(action, selecting: selecting, specialState: state.specialState)
        }
    }

    /// macSKKで取り扱わないキーイベントを処理するかどうかを返す
    func handleUnhandledEvent(_ event: NSEvent) -> Bool {
        if state.specialState != nil {
            return true
        }
        switch state.inputMethod {
        case .normal:
            return false
        case .composing, .selecting:
            return true
        }
    }

    /**
     * 状態がnormalのときのhandle
     */
    func handleNormal(_ action: Action, specialState: SpecialState?) -> Bool {
        switch action.keyEvent {
        case .enter:
            if let specialState {
                if case .register(let registerState) = specialState {
                    if registerState.text.isEmpty {
                        state.inputMode = registerState.prev.mode
                        state.inputMethod = .composing(registerState.prev.composing)
                        state.specialState = nil
                        updateMarkedText()
                    } else {
                        dictionary.add(yomi: registerState.yomi, word: Word(registerState.text))
                        state.specialState = nil
                        state.inputMode = registerState.prev.mode
                        addFixedText(registerState.text)
                    }
                    return true
                } else if case .unregister(let unregisterState) = specialState {
                    if unregisterState.text == "yes" {
                        let word = unregisterState.prev.selecting.candidates[
                            unregisterState.prev.selecting.candidateIndex]
                        _ = dictionary.delete(yomi: unregisterState.prev.selecting.yomi, word: word)
                        state.inputMode = unregisterState.prev.mode
                        state.inputMethod = .normal
                        state.specialState = nil
                        updateMarkedText()
                    } else {
                        state.inputMode = unregisterState.prev.mode
                        updateCandidates(selecting: unregisterState.prev.selecting)
                        state.inputMethod = .selecting(unregisterState.prev.selecting)
                        state.specialState = nil
                        updateMarkedText()
                    }
                    return true
                }
            }
            return false
        case .backspace:
            if let specialState = state.specialState {
                state.specialState = specialState.dropLast()
                updateMarkedText()
                return true

            } else {
                return false
            }
        case .space:
            switch state.inputMode {
            case .eisu:
                addFixedText("　")
            default:
                addFixedText(" ")
            }
            return true
        case .stickyShift:
            switch state.inputMode {
            case .hiragana, .katakana, .hankaku:
                state.inputMethod = .composing(ComposingState(isShift: true, text: [], okuri: nil, romaji: ""))
                updateMarkedText()
            case .eisu:
                addFixedText("；")
            case .direct:
                addFixedText(";")
            }
            return true
        case .printable(let input):
            return handleNormalPrintable(input: input, action: action, specialState: specialState)
        case .ctrlJ:
            if case .unregister = specialState {
                return true
            } else {
                state.inputMode = .hiragana
                inputMethodEventSubject.send(.modeChanged(.hiragana, action.cursorPosition))
                return true
            }
        case .cancel:
            if let specialState = state.specialState {
                switch specialState {
                case .register(let registerState):
                    state.inputMode = registerState.prev.mode
                    state.inputMethod = .composing(registerState.prev.composing)
                case .unregister(let unregisterState):
                    state.inputMode = unregisterState.prev.mode
                    updateCandidates(selecting: unregisterState.prev.selecting)
                    state.inputMethod = .selecting(unregisterState.prev.selecting)
                }
                state.specialState = nil
                updateMarkedText()
                return true
            } else {
                return false
            }
        case .ctrlQ:
            switch state.inputMode {
            case .hiragana, .katakana:
                state.inputMode = .hankaku
                inputMethodEventSubject.send(.modeChanged(.hankaku, action.cursorPosition))
                return true
            case .hankaku:
                state.inputMode = .hiragana
                inputMethodEventSubject.send(.modeChanged(.hiragana, action.cursorPosition))
                return true
            default:
                return false
            }
        case .left:
            if let specialState = state.specialState {
                state.specialState = specialState.moveCursorLeft()
                updateMarkedText()
                return true
            } else {
                return false
            }
        case .right:
            if let specialState = state.specialState {
                state.specialState = specialState.moveCursorRight()
                updateMarkedText()
                return true
            } else {
                return false
            }
        case .ctrlA:
            if let specialState = state.specialState {
                state.specialState = specialState.moveCursorFirst()
                updateMarkedText()
                return true
            } else {
                return false
            }
        case .ctrlE:
            if let specialState = state.specialState {
                state.specialState = specialState.moveCursorLast()
                updateMarkedText()
                return true
            } else {
                return false
            }
        case .down, .up:
            if state.specialState != nil {
                return true
            } else {
                return false
            }
        case .ctrlY:
            if case .register = state.specialState {
                if let text = Pasteboard.getString() {
                    addFixedText(text)
                    return true
                } else {
                    return false
                }
            } else {
                return false
            }
        }
    }

    /// 状態がnormalのときのprintableイベントのhandle
    func handleNormalPrintable(input: String, action: Action, specialState: SpecialState?) -> Bool {
        if input.lowercased() == "q" {
            switch state.inputMode {
            case .hiragana:
                state.inputMode = .katakana
                inputMethodEventSubject.send(.modeChanged(.katakana, action.cursorPosition))
                return true
            case .katakana, .hankaku:
                state.inputMode = .hiragana
                inputMethodEventSubject.send(.modeChanged(.hiragana, action.cursorPosition))
                return true
            case .eisu:
                break
            case .direct:
                break
            }
        } else if input.lowercased() == "l" {
            switch state.inputMode {
            case .hiragana, .katakana, .hankaku:
                if action.shiftIsPressed() {
                    state.inputMode = .eisu
                    inputMethodEventSubject.send(.modeChanged(.eisu, action.cursorPosition))
                } else {
                    state.inputMode = .direct
                    inputMethodEventSubject.send(.modeChanged(.direct, action.cursorPosition))
                }
                return true
            case .eisu:
                break
            case .direct:
                break
            }
        } else if input == "/" && !action.shiftIsPressed() {
            switch state.inputMode {
            case .hiragana, .katakana, .hankaku:
                state.inputMode = .direct
                state.inputMethod = .composing(ComposingState(isShift: true, text: [], okuri: nil, romaji: ""))
                inputMethodEventSubject.send(.modeChanged(.direct, action.cursorPosition))
                updateMarkedText()
                return true
            case .eisu, .direct:
                break
            }
        }

        let isAlphabet = input.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
        switch state.inputMode {
        case .hiragana, .katakana, .hankaku:
            if isAlphabet && !action.optionIsPressed() {
                let result = Romaji.convert(input)
                if let moji = result.kakutei {
                    if action.shiftIsPressed() {
                        state.inputMethod = .composing(
                            ComposingState(isShift: true, text: moji.kana.map { String($0) }, romaji: result.input))
                        updateMarkedText()
                    } else {
                        addFixedText(moji.string(for: state.inputMode))
                    }
                } else {
                    state.inputMethod = .composing(
                        ComposingState(isShift: action.shiftIsPressed(), text: [], okuri: nil, romaji: input))
                    updateMarkedText()
                }
            } else {
                // Option-Shift-2のような入力のときには€が入力されるようにする
                if let characters = action.characters() {
                    let result = Romaji.convert(characters)
                    if let moji = result.kakutei {
                        addFixedText(moji.string(for: state.inputMode))
                    } else {
                        addFixedText(characters)
                    }
                }
            }
            return true
        case .eisu:
            if let characters = action.characters() {
                addFixedText(characters.toZenkaku())
            } else {
                logger.error("Can not find printable characters in keyEvent")
                return false
            }
            return true
        case .direct:
            if let characters = action.characters() {
                addFixedText(characters)
            } else {
                logger.error("Can not find printable characters in keyEvent")
                return false
            }
            return true
        }
    }

    func handleComposing(_ action: Action, composing: ComposingState, specialState: SpecialState?) -> Bool {
        let isShift = composing.isShift
        let text = composing.text
        let okuri = composing.okuri
        let romaji = composing.romaji

        switch action.keyEvent {
        case .enter:
            // 未確定ローマ字はn以外は入力されずに削除される. nだけは"ん"として変換する
            let fixedText = composing.string(for: state.inputMode, convertHatsuon: true)
            state.inputMethod = .normal
            addFixedText(fixedText)
            return true
        case .backspace:
            if let newComposingState = composing.dropLast() {
                state.inputMethod = .composing(newComposingState)
            } else {
                state.inputMethod = .normal
            }
            updateMarkedText()
            return true
        case .space:
            if state.inputMode != .direct {
                let converted = Romaji.convert(romaji + " ")
                if converted.kakutei != nil {
                    return handleComposingPrintable(
                        input: " ",
                        converted: converted,
                        action: action,
                        composing: composing,
                        specialState: specialState
                    )
                }
            }
            if text.isEmpty {
                addFixedText(" ")
                state.inputMethod = .normal
                return true
            } else {
                // 未確定ローマ字はn以外は入力されずに削除される. nだけは"ん"として変換する
                // 変換候補がないときは辞書登録へ
                let trimmedComposing = composing.trim()
                let yomiText = trimmedComposing.yomi(for: state.inputMode)
                let candidates = dictionary.refer(yomiText)
                if candidates.isEmpty {
                    if specialState != nil {
                        // 登録中に変換不能な変換をした場合は空文字列に変換する
                        state.inputMethod = .normal
                    } else {
                        // 単語登録に遷移する
                        state.specialState = .register(
                            RegisterState(
                                prev: RegisterState.PrevState(mode: state.inputMode, composing: trimmedComposing),
                                yomi: yomiText))
                        state.inputMethod = .normal
                        state.inputMode = .hiragana
                        inputMethodEventSubject.send(.modeChanged(.hiragana, action.cursorPosition))
                    }
                } else {
                    let selectingState = SelectingState(
                        prev: SelectingState.PrevState(mode: state.inputMode, composing: trimmedComposing),
                        yomi: yomiText, candidates: candidates, candidateIndex: 0,
                        cursorPosition: action.cursorPosition)
                    updateCandidates(selecting: selectingState)
                    state.inputMethod = .selecting(selectingState)
                }
                updateMarkedText()
                return true
            }
        case .stickyShift:
            if case .direct = state.inputMode {
                return handleComposingPrintable(
                    input: ";",
                    converted: Romaji.convert(";"),
                    action: action,
                    composing: composing,
                    specialState: specialState)
            } else {
                if let okuri {
                    // AquaSKKは送り仮名の末尾に"；"をつけて変換処理もしくは単語登録に遷移
                    state.inputMethod = .composing(
                        ComposingState(
                            isShift: isShift, text: text, okuri: okuri + [Romaji.symbolTable[";"]!], romaji: ""))
                    updateMarkedText()
                } else {
                    // 空文字列のときは全角；を入力、それ以外のときは送り仮名モードへ
                    if text.isEmpty {
                        state.inputMethod = .normal
                        addFixedText("；")
                    } else {
                        state.inputMethod = .composing(
                            ComposingState(isShift: true, text: text, okuri: [], romaji: romaji))
                        updateMarkedText()
                    }
                }
                return true
            }
        case .printable(let input):
            return handleComposingPrintable(
                input: input,
                converted: Romaji.convert(romaji + input.lowercased()),
                action: action,
                composing: composing,
                specialState: specialState)
        case .ctrlJ:
            // 入力中文字列を確定させてひらがなモードにする
            addFixedText(composing.string(for: state.inputMode, convertHatsuon: true))
            state.inputMethod = .normal
            state.inputMode = .hiragana
            inputMethodEventSubject.send(.modeChanged(.hiragana, action.cursorPosition))
            return true
        case .cancel:
            if romaji.isEmpty {
                // 下線テキストをリセットする
                state.inputMethod = .normal
            } else {
                state.inputMethod = .composing(ComposingState(isShift: isShift, text: text, okuri: nil, romaji: ""))
            }
            updateMarkedText()
            return true
        case .ctrlQ:
            if okuri == nil {
                if case .direct = state.inputMode {
                    // 全角英数で確定する
                    state.inputMethod = .normal
                    addFixedText(text.map { $0.toZenkaku() }.joined())
                    // TODO: AquaSKKはAbbrevに入る前のモードに戻しているのでそれに合わせる?
                    state.inputMode = .hiragana
                    inputMethodEventSubject.send(.modeChanged(.hiragana, action.cursorPosition))
                } else {
                    // 半角カタカナで確定する。
                    state.inputMethod = .normal
                    addFixedText(composing.string(for: .hankaku, convertHatsuon: false))
                }
                return true
            } else {
                // 送り仮名があるときはなにもしない
                return true
            }
        case .left:
            if okuri == nil { // 一度変換候補選択に遷移してからキャンセルで戻ると送り仮名ありになっている
                if romaji.isEmpty {
                    state.inputMethod = .composing(composing.moveCursorLeft())
                } else {
                    // 未確定ローマ字があるときはローマ字を消す (AquaSKKと同じ)
                    state.inputMethod = .composing(ComposingState(isShift: isShift, text: text, okuri: okuri, romaji: ""))
                }
                updateMarkedText()
            }
            return true
        case .right:
            if okuri == nil { // 一度変換候補選択に遷移してからキャンセルで戻ると送り仮名ありになっている
                if romaji.isEmpty {
                    state.inputMethod = .composing(composing.moveCursorRight())
                } else {
                    state.inputMethod = .composing(ComposingState(isShift: isShift, text: text, okuri: okuri, romaji: ""))
                }
                updateMarkedText()
            }
            return true
        case .ctrlA:
            if okuri == nil { // 一度変換候補選択に遷移してからキャンセルで戻ると送り仮名ありになっている
                if romaji.isEmpty {
                    state.inputMethod = .composing(composing.moveCursorFirst())
                } else {
                    // 未確定ローマ字があるときはローマ字を消す (AquaSKKと同じ)
                    state.inputMethod = .composing(ComposingState(isShift: isShift, text: text, okuri: okuri, romaji: ""))
                }
                updateMarkedText()
            }
            return true
        case .ctrlE:
            if okuri == nil { // 一度変換候補選択に遷移してからキャンセルで戻ると送り仮名ありになっている
                if romaji.isEmpty {
                    state.inputMethod = .composing(composing.moveCursorLast())
                } else {
                    state.inputMethod = .composing(ComposingState(isShift: isShift, text: text, okuri: okuri, romaji: ""))
                }
                updateMarkedText()
            }
            return true
        case .up, .down, .ctrlY:
            return true
        }
    }

    func handleComposingPrintable(
        input: String, converted: Romaji.ConvertedMoji, action: Action, composing: ComposingState,
        specialState: SpecialState?
    ) -> Bool {
        let isShift = composing.isShift
        let text = composing.text
        let okuri = composing.okuri

        if input.lowercased() == "q" && converted.kakutei == nil {
            if okuri == nil {
                // AquaSKKの挙動に合わせてShift-Qのときは送り無視で確定、次の入力へ進む
                if action.shiftIsPressed() {
                    state.inputMethod = .composing(ComposingState(isShift: true, text: [], okuri: nil, romaji: ""))
                    switch state.inputMode {
                    case .hiragana:
                        addFixedText(text.joined())
                        return true
                    case .katakana, .hankaku:
                        addFixedText(text.map { $0.toKatakana() }.joined())
                        return true
                    case .direct:
                        // 普通にqを入力させる
                        break
                    default:
                        fatalError("inputMode=\(state.inputMode), handleComposingでShift-Qが入力された")
                    }
                } else {
                    // ひらがな入力中ならカタカナ、カタカナ入力中ならひらがな、半角カタカナ入力中なら全角カタカナで確定する。
                    // 未確定ローマ字はn以外は入力されずに削除される. nだけは"ん"が入力されているとする
                    let newText: [String] = composing.romaji == "n" ? composing.subText() + ["ん"] : composing.subText()
                    state.inputMethod = .normal
                    switch state.inputMode {
                    case .hiragana, .hankaku:
                        addFixedText(newText.joined().toKatakana())
                        return true
                    case .katakana:
                        addFixedText(newText.joined())
                        return true
                    case .direct:
                        // 普通にqを入力させる
                        break
                    default:
                        fatalError("inputMode=\(state.inputMode), handleComposingでqが入力された")
                    }
                }
            } else {
                // 送り仮名があるときはローマ字部分をリセットする
                state.inputMethod = .composing(
                    ComposingState(isShift: isShift, text: text, okuri: okuri, romaji: ""))
                return false
            }
        } else if input.lowercased() == "l" && converted.kakutei == nil {
            // 入力済みを確定してからlを打ったのと同じ処理をする
            if okuri == nil {
                switch state.inputMode {
                case .hiragana, .katakana, .hankaku:
                    state.inputMethod = .normal
                    addFixedText(composing.string(for: state.inputMode, convertHatsuon: true))
                    return handleNormal(action, specialState: specialState)
                case .direct:
                    // 普通にlを入力させる
                    break
                default:
                    fatalError("inputMode=\(state.inputMode), handleComposingでlが入力された")
                }
            } else {
                // 送り仮名があるときはローマ字部分をリセットする
                state.inputMethod = .composing(
                    ComposingState(isShift: isShift, text: text, okuri: okuri, romaji: ""))
                return false
            }
        }
        switch state.inputMode {
        case .hiragana, .katakana, .hankaku:
            // ローマ字が確定してresult.inputがない
            // StickyShiftでokuriが[]になっている、またはShift押しながら入力した
            if let moji = converted.kakutei {
                if converted.input.isEmpty {
                    if text.isEmpty || (okuri == nil && !action.shiftIsPressed()) || composing.cursor == 0 {
                        if isShift || action.shiftIsPressed() {
                            state.inputMethod = .composing(composing.appendText(moji).resetRomaji().with(isShift: true))
                        } else {
                            state.inputMethod = .normal
                            addFixedText(moji.string(for: state.inputMode))
                            return true
                        }
                    } else {
                        // 送り仮名が1文字以上確定した時点で変換を開始する
                        // 変換候補がないときは辞書登録へ
                        // カーソル位置がnilじゃないときはその前までで変換を試みる
                        let subText: [String] = composing.subText()
                        let yomiText = subText.joined() + (okuri?.first?.firstRomaji ?? moji.firstRomaji)
                        let newComposing = ComposingState(isShift: true,
                                                          text: composing.text,
                                                          okuri: (okuri ?? []) + [moji],
                                                          romaji: "",
                                                          cursor: composing.cursor)
                        let candidates = dictionary.refer(yomiText)
                        if candidates.isEmpty {
                            if specialState != nil {
                                // 登録中に変換不能な変換をした場合は空文字列に変換する
                                state.inputMethod = .normal
                            } else {
                                // 単語登録に遷移する
                                state.specialState = .register(
                                    RegisterState(
                                        prev: RegisterState.PrevState(mode: state.inputMode, composing: newComposing),
                                        yomi: yomiText
                                    ))
                                state.inputMethod = .normal
                                state.inputMode = .hiragana
                                inputMethodEventSubject.send(.modeChanged(.hiragana, action.cursorPosition))
                            }
                        } else {
                            let selectingState = SelectingState(
                                prev: SelectingState.PrevState(mode: state.inputMode, composing: newComposing),
                                yomi: yomiText, candidates: candidates, candidateIndex: 0,
                                cursorPosition: action.cursorPosition)
                            updateCandidates(selecting: selectingState)
                            state.inputMethod = .selecting(selectingState)
                        }
                    }
                } else {  // !result.input.isEmpty
                    // n + 子音入力したときなど
                    if isShift || action.shiftIsPressed() {
                        if let okuri {
                            state.inputMethod = .composing(
                                ComposingState(
                                    isShift: true,
                                    text: text,
                                    okuri: okuri + [moji],
                                    romaji: converted.input))
                        } else {
                            state.inputMethod = .composing(
                                ComposingState(
                                    isShift: true,
                                    text: text + [moji.kana],
                                    okuri: action.shiftIsPressed() ? [] : nil,
                                    romaji: converted.input))
                        }
                    } else {
                        addFixedText(moji.string(for: state.inputMode))
                        state.inputMethod = .composing(
                            ComposingState(isShift: false, text: [], okuri: nil, romaji: converted.input))
                    }
                }
                updateMarkedText()
            } else {  // converted.kakutei == nil
                if !text.isEmpty && okuri == nil && action.shiftIsPressed() {
                    state.inputMethod = .composing(
                        ComposingState(isShift: isShift,
                                       text: text,
                                       okuri: [],
                                       romaji: converted.input,
                                       cursor: composing.cursor))
                } else {
                    state.inputMethod = .composing(
                        ComposingState(isShift: isShift,
                                       text: text,
                                       okuri: okuri,
                                       romaji: converted.input,
                                       cursor: composing.cursor))
                }
                updateMarkedText()
            }
            return true
        case .direct:
            state.inputMethod = .composing(
                ComposingState(
                    isShift: isShift,
                    text: text + [action.characters() ?? ""],
                    okuri: nil,
                    romaji: ""))
            updateMarkedText()
            return true
        default:
            fatalError("inputMode=\(state.inputMode), handleComposingで\(input)が入力された")
        }
    }

    func handleSelecting(_ action: Action, selecting: SelectingState, specialState: SpecialState?) -> Bool {
        switch action.keyEvent {
        case .enter:
            dictionary.add(yomi: selecting.yomi, word: selecting.candidates[selecting.candidateIndex])
            updateCandidates(selecting: nil)
            state.inputMethod = .normal
            addFixedText(selecting.fixedText())
            return true
        case .backspace, .up:
            let diff: Int
            if selecting.candidateIndex >= inlineCandidateCount && action.keyEvent == .backspace {
                // 前ページの先頭
                diff =
                    -((selecting.candidateIndex - inlineCandidateCount) % displayCandidateCount) - displayCandidateCount
            } else {
                diff = -1
            }
            if selecting.candidateIndex + diff >= 0 {
                let newSelectingState = selecting.addCandidateIndex(diff: diff)
                updateCandidates(selecting: newSelectingState)
                state.inputMethod = .selecting(newSelectingState)
            } else {
                updateCandidates(selecting: nil)
                state.inputMethod = .composing(selecting.prev.composing)
                state.inputMode = selecting.prev.mode
            }
            updateMarkedText()
            return true
        case .space, .down:
            let diff: Int
            if selecting.candidateIndex >= inlineCandidateCount && action.keyEvent == .space {
                // 次ページの先頭
                diff = displayCandidateCount - (selecting.candidateIndex - inlineCandidateCount) % displayCandidateCount
            } else {
                diff = 1
            }
            if selecting.candidateIndex + diff < selecting.candidates.count {
                let newSelectingState = selecting.addCandidateIndex(diff: diff)
                state.inputMethod = .selecting(newSelectingState)
                updateCandidates(selecting: newSelectingState)
            } else {
                if specialState != nil {
                    state.inputMethod = .normal
                    state.inputMode = selecting.prev.mode
                } else {
                    state.specialState = .register(
                        RegisterState(
                            prev: RegisterState.PrevState(
                                mode: selecting.prev.mode,
                                composing: selecting.prev.composing),
                            yomi: selecting.yomi))
                    state.inputMethod = .normal
                    state.inputMode = .hiragana
                    inputMethodEventSubject.send(.modeChanged(.hiragana, action.cursorPosition))
                }
                updateCandidates(selecting: nil)
            }
            updateMarkedText()
            return true
        case .stickyShift, .ctrlJ, .ctrlQ:
            // 選択中候補で確定
            dictionary.add(yomi: selecting.yomi, word: selecting.candidates[selecting.candidateIndex])
            updateCandidates(selecting: nil)
            addFixedText(selecting.fixedText())
            state.inputMethod = .normal
            return handleNormal(action, specialState: nil)
        case .printable(let input):
            if input == "x" && action.shiftIsPressed() {
                state.specialState = .unregister(
                    UnregisterState(prev: UnregisterState.PrevState(mode: state.inputMode, selecting: selecting)))
                state.inputMethod = .normal
                state.inputMode = .direct
                updateCandidates(selecting: nil)
                updateMarkedText()
                return true
            } else if selecting.candidateIndex >= inlineCandidateCount {
                if let index = Int(input), 1 <= index && index <= 9 {
                    let diff = index - 1 - (selecting.candidateIndex - inlineCandidateCount) % displayCandidateCount
                    if selecting.candidateIndex + diff < selecting.candidates.count {
                        let newSelecting = selecting.addCandidateIndex(diff: diff)
                        dictionary.add(
                            yomi: newSelecting.yomi, word: newSelecting.candidates[newSelecting.candidateIndex])
                        updateCandidates(selecting: nil)
                        state.inputMethod = .normal
                        addFixedText(newSelecting.fixedText())
                        return true
                    }
                }
            }
            // 選択中候補で確定
            dictionary.add(yomi: selecting.yomi, word: selecting.candidates[selecting.candidateIndex])
            updateCandidates(selecting: nil)
            addFixedText(selecting.fixedText())
            state.inputMethod = .normal
            return handleNormal(action, specialState: nil)
        case .cancel:
            state.inputMethod = .composing(selecting.prev.composing)
            state.inputMode = selecting.prev.mode
            updateCandidates(selecting: nil)
            updateMarkedText()
            return true
        case .left, .right:
            // AquaSKKと同様に何もしない (IMKCandidates表示時はそちらの移動に使われる)
            return true
        case .ctrlA:
            // 現ページの先頭
            let diff = -(selecting.candidateIndex - inlineCandidateCount) % displayCandidateCount
            if diff < 0 {
                let newSelectingState = selecting.addCandidateIndex(diff: diff)
                state.inputMethod = .selecting(newSelectingState)
                updateCandidates(selecting: newSelectingState)
                updateMarkedText()
            }
            return true
        case .ctrlE:
            // 現ページの末尾
            let diff = min(
                displayCandidateCount - (selecting.candidateIndex - inlineCandidateCount) % displayCandidateCount,
                selecting.candidates.count - selecting.candidateIndex - 1
            )
            if diff > 0 {
                let newSelectingState = selecting.addCandidateIndex(diff: diff)
                state.inputMethod = .selecting(newSelectingState)
                updateCandidates(selecting: newSelectingState)
                updateMarkedText()
            }
            return true
        case .ctrlY:
            return true
        }
    }

    func setMode(_ mode: InputMode) {
        state.inputMode = mode
    }

    /// 現在の入力中文字列を確定して状態を入力前に戻す。カーソル位置が文字列の途中でも末尾にあるものとして扱う
    ///
    /// 仕様はどうあるべきか検討中。不明なものは仮としている。
    /// - 状態がNormalおよびローマ字未確定入力中
    ///   - 空文字列で確定させる
    ///   - nだけ入力してるときも空文字列 (仮)
    /// - 状態がComposing (未確定)
    ///   - "▽" より後ろの文字列を確定で入力する
    /// - 状態がSelecting (変換候補選択中)
    ///   - 現在選択中の変換候補の "▼" より後ろの文字列を確定で入力する
    ///   - ユーザー辞書には登録しない (仮)
    /// - 状態が上記でないときは仮で次のように実装してみる。いろんなソフトで不具合があるかどうかを見る
    ///   - 状態がRegister (単語登録中)
    ///     - 空文字列で確定する
    ///   - 状態がUnregister (ユーザー辞書から削除するか質問中)
    ///     - 空文字列で確定する
    func commitComposition() {
        if state.specialState != nil {
            state.inputMethod = .normal
            state.specialState = nil
            addFixedText("")
        } else {
            switch state.inputMethod {
            case .normal:
                return
            case .composing(let composing):
                let fixedText = composing.string(for: state.inputMode, convertHatsuon: false)
                state.inputMethod = .normal
                addFixedText(fixedText)
            case .selecting(let selecting):
                // エンター押したときと違って辞書登録はスキップ (仮)
                updateCandidates(selecting: nil)
                state.inputMethod = .normal
                addFixedText(selecting.fixedText())
            }
        }
    }

    private func addFixedText(_ text: String) {
        if let specialState = state.specialState {
            // state.markedTextを更新してinputMethodEventSubjectにstate.displayText()をsendする
            state.specialState = specialState.appendText(text)
            inputMethodEventSubject.send(.markedText(state.displayText()))
        } else {
            if text.isEmpty {
                // 空文字列で確定するときは先にmarkedTextを削除する
                // (そうしないとエディタには未確定文字列が残ってしまう)
                inputMethodEventSubject.send(.markedText(MarkedText([])))
            } else {
                inputMethodEventSubject.send(.fixedText(text))
            }
        }
    }

    /// 現在のMarkedText状態をinputMethodEventSubject.sendする
    private func updateMarkedText() {
        inputMethodEventSubject.send(.markedText(state.displayText()))
    }

    /// 現在の変換候補選択状態をcandidateEventSubject.sendする
    private func updateCandidates(selecting: SelectingState?) {
        if let selecting {
            if selecting.candidateIndex < inlineCandidateCount {
                candidateEventSubject.send(
                    Candidates(page: nil,
                               selected: selecting.candidates[selecting.candidateIndex],
                               cursorPosition: selecting.cursorPosition))
            } else {
                var start = selecting.candidateIndex - inlineCandidateCount
                let currentPage = start / displayCandidateCount
                let totalPageCount = (selecting.candidates.count - inlineCandidateCount - 1) / displayCandidateCount + 1
                start = start - start % displayCandidateCount + inlineCandidateCount
                let candidates = selecting.candidates[start..<min(start + displayCandidateCount, selecting.candidates.count)]
                candidateEventSubject.send(
                    Candidates(page: Candidates.Page(words: Array(candidates), current: currentPage, total: totalPageCount),
                               selected: selecting.candidates[selecting.candidateIndex],
                               cursorPosition: selecting.cursorPosition))
            }
        } else {
            candidateEventSubject.send(nil)
        }
    }

    /// StateMachine外で選択されている変換候補が更新されたときに通知される
    func didSelectCandidate(_ candidate: Word) {
        if case .selecting(var selecting) = state.inputMethod {
            if let candidateIndex = selecting.candidates.firstIndex(of: candidate) {
                selecting.candidateIndex = candidateIndex
                state.inputMethod = .selecting(selecting)
                updateMarkedText()
            }
        }
    }

    /// StateMachine外で選択されている変換候補が二回選択されたときに通知される
    func didDoubleSelectCandidate(_ candidate: Word) {
        if case .selecting(let selecting) = state.inputMethod {
            dictionary.add(yomi: selecting.yomi, word: candidate)
            updateCandidates(selecting: nil)
            state.inputMethod = .normal
            addFixedText(candidate.word)
        }
    }
}
