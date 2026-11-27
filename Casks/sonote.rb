cask "sonote" do
  version "1.5.1"
  sha256 "6a0c3f2020e72a51565a11552b5870cbbca7b6d8ceb4b5089d9f99d1577b43f8"

  url "https://github.com/eeachen4/Sonote/releases/download/v#{version}/Sonote-#{version}-arm64.dmg"
  name "Sonote"
  desc "Native macOS AI meeting minutes powered 100% on-device by Apple Silicon MLX"
  homepage "https://github.com/eeachen4/Sonote"

  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "Sonote.app"

  caveats <<~EOS
    Sonote is currently self-signed for open-source distribution.
    If macOS Gatekeeper blocks the first launch, run:
      xattr -cr /Applications/Sonote.app
  EOS

  zap trash: [
    "~/Library/Application Support/Sonote",
    "~/Library/Preferences/com.sonote.app.plist",
  ]
end
