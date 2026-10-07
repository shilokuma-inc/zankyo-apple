//
//  Zankyo.swift
//  Zankyo
//
//  Created by 村石 拓海 on 2024/05/12.
//

import SwiftUI

@main
struct Zankyo: App {
    /// ウィンドウとイマーシブ空間（visionOS）で同じ入力を使う
    @State private var motionInput: any MotionInput = MotionInputFactory.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView(
                client: BeatsaverAPIClient(),
                downloader: MapDownloader(),
                motionInput: motionInput,
                metronome: ClickMetronome()
            )
            #if os(visionOS)
            .modifier(OpensHeadTrackingSpace())
            #endif
        }
        #if os(visionOS)
        // ARKit の頭の向きはイマーシブ空間の中でしか取れない（Discussion #3 Q7）
        ImmersiveSpace(id: HeadTrackingSpace.id) {
            HeadTrackingSpaceView(input: motionInput as? HeadTrackingMotionInput)
        }
        #endif
    }
}
