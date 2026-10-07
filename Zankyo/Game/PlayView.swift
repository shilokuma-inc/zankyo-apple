import SwiftUI

/// プレイ画面。縦持ち・片手が前提で、手で触るのは画面下 1/3 の一時停止だけ（Discussion #3）
///
/// ノーツは上から判定の線へ降りてきて、線に重なる時刻に向きの矢印の方へ首を振る
struct PlayView: View {
    let session: GameSession
    let onExit: () -> Void

    /// ノーツが画面の上端から判定の線に届くまでの秒
    static let approachTime: TimeInterval = 1.5

    var body: some View {
        VStack(spacing: 0) {
            header
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
        }
        .padding()
        .onAppear { Self.setIdleTimerDisabled(true) }
        .onDisappear {
            Self.setIdleTimerDisabled(false)
            session.pause()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text(session.score, format: .number)
                    .font(.largeTitle.monospacedDigit().bold())
                Text("コンボ \(session.combo)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("×\(session.multiplier)")
                .font(.title.monospacedDigit().bold())
                .foregroundStyle(.tint)
        }
        .accessibilityElement(children: .combine)
    }

    private var lane: some View {
        GeometryReader { proxy in
            let hitY = proxy.size.height * 0.85
            let centerX = proxy.size.width / 2
            ZStack {
                Rectangle()
                    .fill(.tint.opacity(0.4))
                    .frame(height: 3)
                    .position(x: centerX, y: hitY)
                ForEach(visibleNotes, id: \.time) { note in
                    let remaining = note.time - session.currentTime
                    NoteMark(direction: note.direction)
                        .position(x: centerX, y: hitY - remaining / Self.approachTime * hitY)
                        .opacity(remaining < -0.2 ? 0 : 1)
                }
                if let judgement = session.lastJudgement {
                    JudgementLabel(judgement: judgement)
                        .position(x: centerX, y: hitY + 28)
                        .id(judgement)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// 画面に出すノーツ（判定の線に届く前の数個）
    private var visibleNotes: [FaceNote] {
        Array(session.judge.remainingNotes.prefix { $0.time - session.currentTime <= Self.approachTime }.prefix(8))
    }

    @ViewBuilder private var controls: some View {
        switch session.phase {
        case .ready:
            if session.canStart {
                Button(action: session.start) {
                    Text("始める").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                MotionRequirementView(status: session.input.status)
            }
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
            VStack(spacing: 8) {
                Text("スコア \(session.score) / \(session.judge.maxScore)")
                    .font(.headline.monospacedDigit())
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

/// 1 つのノーツ。向きは矢印、方向不問は丸
private struct NoteMark: View {
    let direction: SwingDirection?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 48, weight: .bold))
            .foregroundStyle(.tint)
            .background(Circle().fill(.background).padding(4))
    }

    private var symbol: String {
        switch direction {
        case .up: "arrow.up.circle.fill"
        case .down: "arrow.down.circle.fill"
        case .left: "arrow.left.circle.fill"
        case .right: "arrow.right.circle.fill"
        case nil: "circle.circle.fill"
        }
    }
}

/// 直近の判定の表示
private struct JudgementLabel: View {
    let judgement: Judgement

    var body: some View {
        Text(text)
            .font(.title3.bold().monospacedDigit())
            .foregroundStyle(color)
    }

    private var text: String {
        switch judgement {
        case .hit(_, let score, _): "\(score.total)"
        case .badCut: "向き違い"
        case .miss: "ミス"
        }
    }

    private var color: Color {
        switch judgement {
        case .hit: .primary
        case .badCut, .miss: .red
        }
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
