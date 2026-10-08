import SwiftUI

/// プレイ画面。縦持ち・片手が前提で、手で触るのは画面下 1/3 の一時停止だけ（Discussion #3）
///
/// ノーツは上から判定の線へ降りてきて、線の上のターゲット枠に収まる時刻に頭を振る（遊び方によっては矢印の向きに振る）。
/// 画面を開くとカウントダウンのあと自動で曲が始まる。一時停止すると、再開・最初から・終了を選べる。
/// 最後まで遊ぶと、レーンの上に「FINISH」を出してから結果画面に移る（タップで早送りできる）
struct PlayView: View {
    let session: GameSession
    /// 頭の動きの見える化に使う。nil なら出さない
    var motion: MotionMonitor?
    /// 曲のジャケット画像（譜面 ZIP の画像）
    var cover: CGImage?
    /// 譜面 ZIP に画像が無いときに取りに行く beatsaver の画像
    var coverURL: URL?
    /// 結果画面に出す曲の情報（nil なら出さない）
    var song: PlayedSong?
    /// 最初からやり直す・もう一度遊ぶ（nil ならボタンを出さない）
    var onRetry: (() -> Void)?
    let onExit: () -> Void

    /// カウントダウンで出している数字。数えていなければ nil
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    /// 曲が始まる前に一時停止を押した（カウントダウンを止めてメニューを出している）
    @State private var isHoldingStart = false
    /// 「FINISH」を見せ終えて、結果画面を出している
    @State private var isShowingResult = false
    @State private var resultTask: Task<Void, Never>?

    /// カウントダウンの始めの数と、1 つ数える秒
    static let countdownFrom = 3
    static let countdownStep: TimeInterval = 0.8
    /// 曲を終えてから結果画面を出すまで、「FINISH」を見せる秒
    static let finishHold: TimeInterval = 2.2

    /// ノーツが画面の上端から判定の線に届くまでの秒
    static let approachTime: TimeInterval = 1.5
    /// 判定の線の上でのノーツの大きさ
    static let noteSize: CGFloat = 64

    /// 判定の表示の文字の高さ（文字の大きさの設定に合わせる）
    @ScaledMetric(relativeTo: .title2) private var judgementLabelHeight: CGFloat = 36

    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if isShowingResult, session.phase == .finished, let result = session.result, let breakdown = session.breakdown {
                ResultView(
                    result: result,
                    breakdown: breakdown,
                    previousBest: session.previousBest,
                    isNewRecord: session.isNewRecord,
                    song: song,
                    cover: cover,
                    coverURL: coverURL,
                    style: session.style,
                    scoreBreakdown: session.judge.breakdown,
                    onRetry: onRetry,
                    onClose: onExit
                )
                .transition(.opacity)
            } else {
                playContent
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isShowingResult)
        // 最後まで遊んだら、「FINISH」を少し見せてから結果画面に移る
        .onChange(of: session.phase) {
            guard session.phase == .finished, session.result != nil else { return }
            resultTask = Task {
                try? await Task.sleep(for: .seconds(Self.finishHold))
                guard !Task.isCancelled else { return }
                isShowingResult = true
            }
        }
        .onAppear {
            Self.setIdleTimerDisabled(true)
            startIfReady()
        }
        // イヤホンが外れたら（始める前でも再開の前でも）数えるのを止める。つながって始められるようになったら、自動で数え始める
        .onChange(of: session.canStart) {
            if !session.canStart {
                cancelCountdown()
            }
            startIfReady()
        }
        .onDisappear {
            Self.setIdleTimerDisabled(false)
            cancelCountdown()
            resultTask?.cancel()
            session.pause()
        }
    }

    /// Beat Saber にならい、空間の奥から光るノーツが飛んでくる見た目にする（色はテーマに従う）。レーンは画面の端まで広げる
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
                } else if session.phase == .finished, let result = session.result {
                    FinishOverlay(isFullCombo: result.isFullCombo)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(palette.panel.opacity(0.35))
                        .contentShape(.rect)
                        .onTapGesture(perform: showResult)
                        .accessibilityAction(named: "結果を見る", showResult)
                } else if session.phase == .ready, !session.canStart {
                    MotionRequirementView(status: session.input.status)
                        .padding()
                        .background(palette.panel.opacity(0.6), in: .rect(cornerRadius: 24))
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
                    palette.panel.opacity(0.45)
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
        .preferredColorScheme(palette.colorScheme)
    }

    /// 一時停止のメニューを出している（再開のカウントダウン中は隠す）
    private var isMenuShown: Bool {
        isHoldingStart || (session.phase == .paused && countdown == nil)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            CoverThumbnail(image: cover, url: coverURL)
            ScoreReadout(score: session.score, combo: session.combo, emptySwings: session.judge.emptySwingCount)
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
                HitTarget(
                    notes: visibleNotes.map { item in
                        HitTarget.Note(index: item.index, remaining: item.note.time - session.currentTime, direction: item.note.direction)
                    },
                    judgedRemaining: session.lastJudgement.map { $0.note.time - session.currentTime },
                    noteSize: Self.noteSize
                )
                .position(x: geometry.centerX, y: geometry.hitY)
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
                        rules: session.judge.rules,
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
            // 結果があれば、「FINISH」を見せたあと body がリザルト画面に切り替わる。結果が無いのは始められずに終えたとき
            if session.result == nil {
                VStack(spacing: 12) {
                    Text("曲を再生できませんでした。")
                        .foregroundStyle(palette.ink)
                    Button("閉じる", action: onExit)
                        .buttonStyle(NeonButtonStyle(prominent: true))
                }
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
        runCountdown {
            // 数えている間に外れていたら始めない（つながり直したら数え直す）
            guard session.phase == .ready, session.canStart else { return }
            session.start()
        }
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

    /// 「FINISH」を待たずに結果画面を出す
    private func showResult() {
        resultTask?.cancel()
        isShowingResult = true
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
