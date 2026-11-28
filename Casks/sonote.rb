cask "sonote" do
  version "1.8.0"
  sha256 "8e42aef2fa7f5d45a978175203daa46f83bc177ff67e9f936bf22f409879126a"

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
