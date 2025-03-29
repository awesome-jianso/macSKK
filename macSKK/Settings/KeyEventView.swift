// SPDX-FileCopyrightText: 2023 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG

import SwiftUI

struct KeyEventView: View {
    @State private var text: String = ""
    @State private var eventMonitor: Any!
    @State private var characters: String = ""
    @State private var charactersIgnoringModifiers: String = ""
    @State private var keyCode: String = ""
    @State private var modifiers: String = ""
    @State private var keyBinding: KeyBinding.Action? = nil

    var body: some View {
        VStack(alignment: .leading) {
            TextField("", text: $text)
                .onAppear {
                    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                        characters = event.characters ?? ""
                        // event.charactersIgnoringModifiersは IMKInputControllerへの入力とは違って
                        // Shiftを押しながらだと変わる記号はそのままになっているという違いがある。
                        // そのためIMKInputControllerに渡されるのに近い「修飾キーがないときの入力」を取得する。
                        if #available(macOS 14, *) {
                            charactersIgnoringModifiers = event.characters(byApplyingModifiers: []) ?? ""
                        } else {
                            charactersIgnoringModifiers = event.charactersWithoutModifiers ?? ""
                        }
                        keyCode = event.keyCode.description
                        var modifiers: [String] = []
                        if event.modifierFlags.contains(.capsLock) {
                            modifiers.append("CapsLock")
                        }
                        if event.modifierFlags.contains(.shift) {
                            modifiers.append("Shift")
                        }
                        if event.modifierFlags.contains(.control) {
                            modifiers.append("Control")
                        }
                        if event.modifierFlags.contains(.option) {
                            modifiers.append("Option")
                        }
                        if event.modifierFlags.contains(.command) {
                            modifiers.append("Command")
                        }
                        if event.modifierFlags.contains(.numericPad) {
                            modifiers.append("NumericPad")
                        }
                        if event.modifierFlags.contains(.help) {
                            modifiers.append("Help")
                        }
                        if event.modifierFlags.contains(.function) {
                            modifiers.append("Fn")
                        }
                        self.modifiers = modifiers.joined(separator: ", ")
                        // toggleKanaとtoggleAndFixKanaが判別できないけどデバッグ機能なのでよしとする
                        self.keyBinding = Global.keyBinding.action(event: event, inputMethodState: .normal)

                        return event
                    }
                }
                .onDisappear {
                    NSEvent.removeMonitor(eventMonitor!)
                }
            Form {
                Section {
                    TextField("KeyBinding", text: .constant(keyBinding?.stringValue ?? ""))
                }
                Section {
                    TextField("KeyCode", text: .constant(keyCode))
                }
                Section {
                    TextField("Characters", text: .constant(characters))
                }
                Section {
                    TextField("CharactersIgnoringModifiers", text: .constant(charactersIgnoringModifiers))
                }
                Section {
                    TextField("Modifiers", text: .constant(modifiers))
                }
            }
            Spacer()
        }
        .padding()
    }
}

struct KeyEventView_Previews: PreviewProvider {
    static var previews: some View {
        KeyEventView()
    }
}

#endif
