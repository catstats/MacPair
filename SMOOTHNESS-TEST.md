# MacPair 0.1.11 RC1 — smoothness comparison / 流畅度对比

This is a test build. The website's stable release remains 0.1.10. No promised wireless frame rate. Pairing remains memory-only; no Keychain access.

## Run on the two Macs

1. Quit the older MacPair on **both** Macs, then open this build on both.
2. Choose Display Mac on the receiving Mac. On the host, choose Extend and the same Default/Retina resolution used before. Connect with the fresh six-digit code.
3. Open **Diagnostics → Compare 1 / 2 / 3 frames** on the host. No action is needed on the receiver.
4. A moving document/window pattern temporarily covers the captured display. The app compares windows in order **2, 1, 3, 3, 1, 2**, with 2 seconds warm-up and 10 seconds measurement each. It independently verifies the selected window for another 12 seconds. About **84 seconds**, or **96 seconds** if a candidate fails verification and two frames are reverified.
5. Do not drag/resize/change resolution or run other codec benchmarks during the comparison. Click the pattern, press Esc, or use Cancel comparison to stop and restore the two-frame default.
6. The pattern closes automatically. **Show smoothness report** reveals the JSON; **Copy diagnostics** includes its text summary. The host writes numbers only under `~/Library/Application Support/MacPair/Performance/`; no screenshots, video, pairing secrets or codes are saved. Share the report in this chat, or tell Codex the run has finished so it can read the local report.

A >=10% throughput gain is required, except a one-frame window may qualify at >=30 baseline FPS if it keeps >=95% throughput and cuts ACK p95 by >=20%. Callback-to-submission-ACK p95 no more than baseline plus max(10 ms, 20%) is required. WindowServer-to-ACK p95 must pass the same guard when available. Repeated runs differing by >25% are inconclusive. Available renderer statistics must show no corruption and <=2% drops. Independent verification must pass again; otherwise the app restores two frames. Selection is for this connection only. Reconnecting starts at two frames.

## What is measured

All times are milliseconds; p95 uses nearest rank over each complete recording, independently of the live one-second UI counters. Before is the measured two-frame baseline **in this run**, not an invented precision for the previously reported approximately 20 FPS. The report includes a separate verification after the comparison.

- `captureAge`: WindowServer display timestamp → capture callback, using the same local Mach clock.
- `captureInterval` / `ackInterval`: spacing of complete capture callbacks / returning submission ACKs; `capture` counts source updates. Static screens do not benchmark the stream ceiling.
- `raw`: age of the latest raw frame at encode admission. Raw captures may be replaced; encoded predictive frames are never dropped.
- `encode`: VideoToolbox encode submission → encoded callback.
- `sendQueue`, `encrypt`, `localTransport`: sender scheduling, AEAD encryption, and local Network.framework content-processed callback. Content-processed is **not** remote receipt.
- `decrypt`, `dispatch`, `sample`, `renderer`: receiver AEAD, parsing-queue wait, compressed-sample construction and wait through submission to AVSampleBufferDisplayLayer. Receiver-local durations return in authenticated ACKs; clocks on different Macs are not subtracted.
- `afterEncodeAck`, `ack`, `sourceAck`: encoded callback / capture callback / WindowServer source timestamp → renderer-submission ACK **including the return trip**.
- `creditStall` / recording duration: time a fresh raw frame waited solely because all frame credits were used. This tests the throughput-window hypothesis directly.
- On macOS 14.4+, optional system renderer counters estimate displayed frames, drops, corruption and average scheduled-time delay. Unavailable counters stay unavailable. They provide **no per-frame decode or physical-display p95**.

ACK FPS measures renderer submissions, not optical display refresh. One-way AWDL delay, hardware-decoder completion inside the display layer and physical presentation latency are not directly measured. Codec-only generated tests measure decode separately; they are not a two-Mac result. For true optical end-to-end p95, external synchronized/high-speed capture is still required.

Production ScreenCaptureKit queueDepth stays **3**, Retina dimensions, bitrate and codec stay unchanged. `--flow-benchmark --capture-source` captures **only an app-owned generated window**, so capture-age/queue data can be checked locally without capturing desktop content. `--capture-depth 5` exists only for an explicitly justified diagnostic rerun; it does not change the app's default.

## 两台 Mac 怎么测

1. 两边都退出旧版，再打开这个测试版。副屏选 Display Mac，主机选 Extend，保持之前的 Default/Retina 设置，输入新的六位码连接。
2. 主机展开 **诊断信息 → 对比 1 / 2 / 3 帧窗口**。副屏无需操作。
3. 动态文档和移动窗口图案会暂时覆盖被捕获的屏幕。自动按 **2、1、3、3、1、2** 帧往返测试，每轮预热 2 秒、记录 10 秒，再独立复测选中的窗口。通常约 **84 秒**，需要回退复测时约 **96 秒**。
4. 测试时保持分辨率，不要同时运行其他编码测试。点击测试图案、按 Esc 或点「取消对比」可停止，并恢复默认两帧。
5. 完成后图案自动关闭。点「显示流畅度报告」打开 JSON，或「复制诊断信息」。告诉 Codex「测好了」，即可读取本机报告继续分析。文件只包含数值，不保存画面、视频、配对密钥或验证码。

通常要求吞吐提升至少 10%；若基线已达 30 FPS，1 帧窗口也可在保持至少 95% 吞吐且 p95 降低至少 20% 时采用。ACK p95 增幅不超过 10 ms 或基线 20%（取较大值）、源画面到 ACK 的 p95 也达标时，才可能采用新窗口；有系统渲染计数时还会检查损坏帧和丢帧。独立复测不通过会自动回退。调整只作用于本次连接，重连恢复两帧。采集队列保持 3，不降低 Retina 分辨率。

**本机加密回环不是两台 Mac 的 AWDL 实测。** ACK 包含回程时间，结束于渲染器提交；它不是实际显示延迟。系统不能提供的解码/物理显示 p95 会明确标为不可用。
