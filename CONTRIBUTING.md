# Contributing

runtime のアルゴリズムは base R で実装し、外部パッケージ、コンパイル済みの QR 実装、FFI、Web サービス、動的リソースを使わないでください。payload のバイト列と明示的な検証を維持してください。不具合を修正する前に回帰テストを追加し、失敗した検証の証拠も保持してください。

意図した編集の後に source manifest を再生成してレビューし、変更不能な source archive を用意してください。その archive を対象に、単体検査、両方の native R version の検証、固定した全 corpus、独立デコーダー、CLI、package consumer を実行してください。その後は source や manifest を変更しないでください。source tree を変更すると、それ以前の source に対応付けた証拠は無効になります。検証対象の実装から期待値の fixture を再生成しないでください。公開 CI が検証するのは Linux のみです。
