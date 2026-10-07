import SwiftUI

/// プレイ画面。縦持ち・片手が前提で、手で触るのは画面下 1/3 の一時停止だけ（Discussion #3）
///
/// ノーツは上から判定の線へ降りてきて、線に重なる時刻に向きの矢印の方へ首を振る
struct PlayView: View {
    let session: GameSession
    /// 曲のジャケット画像（譜面 ZIP の画像）
    var cover: CGImage?
    /// 譜面 ZIP に画像が無いときに取りに行く beatsaver の画像
    var coverURL: URL?
    /// もう一度遊ぶ（nil ならボタンを出さない）
    var onRetry: (() -> Void)?
    let onExit: () -> Void

    /// ノーツが画面の上端から判定の線に届くまでの秒
    static let approachTime: TimeInterval = 1.5
    /// 判定の線の上でのノーツの大きさ
    static let noteSize: CGFloat = 64

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
        .onAppear { Self.setIdleTimerDisabled(true) }
        .onDisappear {
            Self.setIdleTimerDisabled(false)
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
            controls
                .frame(maxWidth: .infinity)
                .frame(minHeight: 160)
                .padding([.horizontal, .bottom])
        }
        .background { PlayfieldBackdrop() }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            CoverThumbnail(image: cover, url: coverURL)
            ScoreReadout(score: session.score, combo: session.combo)
            Spacer()
            MultiplierRing(multiplier: session.multiplier, progress: session.judge.keeper.progressToNextMultiplier)
        }
        .accessibilityElement(children: .combine)
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
                    JudgementEffect(judgement: judgement, noteSize: Self.noteSize)
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
        switch session.phase {
        case .ready:
            VStack(spacing: 8) {
                if session.canStart {
                    Button(action: session.start) {
                        Text("始める").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    MotionRequirementView(status: session.input.status)
                }
                Button(action: onExit) {
                    Text("戻る").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        case .playing:
            Button(action: session.pause) {
                Label("一時停止", systemImage: "pause.fill")
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .paused:
            VStack(spacing: 8) {
                if session.pausedByDisconnection {
                    Text("イヤホンが外れたので止めました。つなぎ直すと再開できます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button(action: session.resume) {
                    Text("再開").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.canStart)
                Button(role: .destructive, action: session.finish) {
                    Text("やめる").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        case .finished:
            // 結果があれば body がリザルト画面に切り替わる。ここに来るのは始められずに終えたとき
            VStack(spacing: 8) {
                Text("曲を再生できませんでした。")
                Button(action: onExit) {
                    Text("閉じる").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
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
    PlayView(
        session: GameSession(
            notes: notes,
            clock: SilentSongClock(duration: 14),
            input: RecordedMotionInput(samples: [])
        ),
        onExit: {}
    )
}
