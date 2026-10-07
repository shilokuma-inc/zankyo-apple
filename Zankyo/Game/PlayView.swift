import SwiftUI

/// プレイ画面。縦持ち・片手が前提で、手で触るのは画面下 1/3 の一時停止だけ（Discussion #3）
///
/// ノーツは上から判定の線へ降りてきて、線に重なる時刻に向きの矢印の方へ首を振る。
/// 画面を開くとカウントダウンのあと自動で曲が始まる。一時停止すると、再開・最初から・終了を選べる
struct PlayView: View {
    let session: GameSession
    /// 頭の動きの見える化に使う。nil なら出さない
    var motion: MotionMonitor?
    /// 曲のジャケット画像（譜面 ZIP の画像）
    var cover: CGImage?
    /// 譜面 ZIP に画像が無いときに取りに行く beatsaver の画像
    var coverURL: URL?
    /// 最初からやり直す・もう一度遊ぶ（nil ならボタンを出さない）
    var onRetry: (() -> Void)?
    let onExit: () -> Void

    /// カウントダウンで出している数字。数えていなければ nil
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    /// 曲が始まる前に一時停止を押した（カウントダウンを止めてメニューを出している）
    @State private var isHoldingStart = false

    /// カウントダウンの始めの数と、1 つ数える秒
    static let countdownFrom = 3
    static let countdownStep: TimeInterval = 0.8

    /// ノーツが画面の上端から判定の線に届くまでの秒
    static let approachTime: TimeInterval = 1.5
    /// 判定の線の上でのノーツの大きさ
    static let noteSize: CGFloat = 64

    /// 判定の表示の文字の高さ（文字の大きさの設定に合わせる）
    @ScaledMetric(relativeTo: .title2) private var judgementLabelHeight: CGFloat = 36

    var body: some View {
        Group {
            if session.phase == .finished, let result = session.result {
                ResultView(
                    result: result,
                    previousBest: session.previousBest,
                    isNewRecord: session.isNewRecord,
                    onRetry: onRetry,
                    onClose: onExit
                )
            } else {
                playContent
            }
        }
        .onAppear {
            Self.setIdleTimerDisabled(true)
            startIfReady()
        }
        // イヤホンがつながって始められるようになったら、自動で数え始める
        .onChange(of: session.canStart) { startIfReady() }
        .onDisappear {
            Self.setIdleTimerDisabled(false)
            cancelCountdown()
            session.pause()
        }
    }

    /// Beat Saber にならい、暗い空間の奥から光るノーツが飛んでくる見た目にする。レーンは画面の端まで広げる
    private var playContent: some View {
        VStack(spacing: 0) {
            header
                .padding([.horizontal, .top])
            TimelineView(.animation(paused: session.phase != .playing)) { context in
                lane
                    .onChange(of: context.date) {
                        session.tick()
                    }
            }
            .frame(maxHeight: .infinity)
            .overlay {
                if let countdown {
                    CountdownOverlay(value: countdown)
                } else if session.phase == .ready, !session.canStart {
                    MotionRequirementView(status: session.input.status)
                        .padding()
                        .background(.black.opacity(0.6), in: .rect(cornerRadius: 24))
                        .padding()
                }
            }
            controls
                .frame(maxWidth: .infinity)
                .frame(minHeight: 120)
                .padding([.horizontal, .bottom])
        }
        .overlay(alignment: .bottom) {
            if isMenuShown {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                    PauseMenu(
                        notice: session.pausedByDisconnection ? "イヤホンが外れたので止めました。つなぎ直すと再開できます。" : nil,
                        canResume: session.canStart,
                        onResume: resume,
                        onRestart: session.phase == .paused ? onRetry.map { retry in { cancelCountdown(); retry() } } : nil,
                        onQuit: quit
                    )
                    .padding()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isMenuShown)
        .background { PlayfieldBackdrop() }
        .preferredColorScheme(.dark)
    }

    /// 一時停止のメニューを出している（再開のカウントダウン中は隠す）
    private var isMenuShown: Bool {
        isHoldingStart || (session.phase == .paused && countdown == nil)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            CoverThumbnail(image: cover, url: coverURL)
            ScoreReadout(score: session.score, combo: session.combo)
                .accessibilityElement(children: .combine)
            Spacer()
            // 始める前は自分で取得して向きを見せ、プレイ中はゲームが取得したものを見せる
            if let motion {
                HeadIndicatorView(monitor: motion, style: .compact, previewsWhenIdle: session.phase == .ready)
                Spacer()
            }
            MultiplierRing(multiplier: session.multiplier, progress: session.judge.keeper.progressToNextMultiplier)
        }
    }

    private var lane: some View {
        GeometryReader { proxy in
            let geometry = PlayfieldGeometry(size: proxy.size, approachTime: Self.approachTime)
            ZStack {
                PlayfieldLane(geometry: geometry)
                PlayfieldGrid(geometry: geometry, currentTime: session.currentTime)
                ForEach(visibleNotes, id: \.index) { item in
                    let remaining = item.note.time - session.currentTime
                    let y = geometry.y(remaining: remaining)
                    NoteBlock(direction: item.note.direction, size: Self.noteSize * geometry.scale(atY: y))
                        .position(x: geometry.centerX, y: y)
                        .opacity(geometry.noteOpacity(remaining: remaining))
                }
                if let judgement = session.lastJudgement {
                    JudgementEffect(
                        judgement: judgement,
                        noteSize: Self.noteSize,
                        labelOffset: geometry.judgementLabelOffset(noteSize: Self.noteSize, labelHeight: judgementLabelHeight)
                    )
                    .position(x: geometry.centerX, y: geometry.hitY)
                    .id(judgement)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// 画面に出すノーツ（判定の線に届く前の数個）。同じ時刻のノーツがあっても ID が重ならないよう、譜面の中の位置を ID にする
    private var visibleNotes: [(index: Int, note: FaceNote)] {
        let remaining = session.judge.remainingNotes
        return zip(remaining.indices, remaining)
            .prefix { $0.1.time - session.currentTime <= Self.approachTime }
            .prefix(8)
            .map { (index: $0.0, note: $0.1) }
    }

    @ViewBuilder private var controls: some View {
        if session.phase == .finished {
            // 結果があれば body がリザルト画面に切り替わる。ここに来るのは始められずに終えたとき
            VStack(spacing: 12) {
                Text("曲を再生できませんでした。")
                    .foregroundStyle(.white)
                Button("閉じる", action: onExit)
                    .buttonStyle(NeonButtonStyle(prominent: true))
            }
        } else if session.phase == .ready, !session.canStart {
            Button("戻る", action: onExit)
                .buttonStyle(NeonButtonStyle())
        } else if !isMenuShown {
            Button(action: pause) {
                Label("一時停止", systemImage: "pause.fill")
            }
            .buttonStyle(NeonButtonStyle())
        }
    }

    /// 始められる状態になっていれば、カウントダウンのあと曲を始める
    private func startIfReady() {
        guard session.phase == .ready, session.canStart, countdown == nil, !isHoldingStart else { return }
        runCountdown { session.start() }
    }

    private func pause() {
        if session.phase == .ready {
            // 曲が始まる前なら、カウントダウンを止めて待つ
            cancelCountdown()
            isHoldingStart = true
        } else if countdown != nil {
            // 再開のカウントダウン中なら、止めたままにする
            cancelCountdown()
        } else {
            session.pause()
        }
    }

    private func resume() {
        if isHoldingStart {
            isHoldingStart = false
            startIfReady()
        } else {
            runCountdown { session.resume() }
        }
    }

    private func quit() {
        cancelCountdown()
        onExit()
    }

    /// 数え終えたら `action` を呼ぶ。途中で取り消されたら呼ばない
    private func runCountdown(then action: @escaping () -> Void) {
        countdownTask?.cancel()
        countdownTask = Task {
            for value in (1...Self.countdownFrom).reversed() {
                withAnimation(.easeOut(duration: 0.25)) { countdown = value }
                try? await Task.sleep(for: .seconds(Self.countdownStep))
                guard !Task.isCancelled else { return }
            }
            countdown = nil
            action()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    /// プレイ中は画面を消さない（iOS のみ。macOS / visionOS は OS に任せる）
    private static func setIdleTimerDisabled(_ isDisabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = isDisabled
        #endif
    }
}

#Preview {
    let notes = (0..<16).map { index in
        FaceNote(beat: Double(index * 2), time: 2 + Double(index) * 0.6, direction: SwingDirection.allCases[index % 4])
    }
    let motion = MotionMonitor(base: RecordedMotionInput(samples: []))
    PlayView(
        session: GameSession(
            notes: notes,
            clock: SilentSongClock(duration: 14),
            input: motion
        ),
        motion: motion,
        onExit: {}
    )
}
