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
    @State private var motionInput: any MotionInput
    /// 画面に頭の動きを出すため、入力を包んだもの。ゲームとキャリブレーションはこちらを使う
    @State private var motion: MotionMonitor
    @State private var library: LibraryStore

    init() {
        let input = MotionInputFactory.makeDefault()
        _motionInput = State(initialValue: input)
        _motion = State(initialValue: MotionMonitor(base: input, detection: SwingSensitivityStore().detection))
        // 取り込みをしなくても遊べるよう、初回はサンプル楽曲をライブラリに入れておく
        let library = LibraryStore()
        SampleSongInstaller().installIfNeeded(into: library)
        _library = State(initialValue: library)
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                client: BeatsaverAPIClient(),
                downloader: MapDownloader(),
                motion: motion,
                metronome: ClickMetronome(),
                library: library
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
