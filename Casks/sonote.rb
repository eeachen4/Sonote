cask "sonote" do
  version "1.6.0"
  sha256 "2517f61b55f1646e97a151ae0ee7a94671df4f8f8e09ca3a67b0a3ca5e3d3abd"

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
