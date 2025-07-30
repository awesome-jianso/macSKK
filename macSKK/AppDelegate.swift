// SPDX-FileCopyrightText: 2023 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Global.dictionary.hasUnsavedChanges {
            logger.log("アプリケーションが終了する前にユーザー辞書の永続化を行います")
            Global.dictionary.save()
        }
        return .terminateNow
    }
}
