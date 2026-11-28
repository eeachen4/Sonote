cask "sonote" do
  version "1.7.0"
  sha256 "e96a190b82fda891fa0ed8790177b16bc1e1e0efbf2301c053485865337f64f9"

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
