//
//  Zankyo.swift
//  Zankyo
//
//  Created by 村石 拓海 on 2024/05/12.
//

import SwiftUI

@main
struct Zankyo: App {
    var body: some Scene {
        WindowGroup {
            RootView(client: BeatsaverAPIClient())
        }
    }
}
